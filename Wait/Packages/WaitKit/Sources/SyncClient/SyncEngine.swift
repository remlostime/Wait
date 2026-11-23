//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import Domain
import Foundation
import IdentifiedCollections
import Logging
import Persistence
import Sharing

// MARK: - SyncEngine

/// The client half of overview §8.5. Single-flight: a `sync()` call made during a run joins that run and asks it to
/// run once more afterwards, so edits made during the run are pushed too. Each run makes at most `maxRounds` requests.
public actor SyncEngine {
  // MARK: Lifecycle

  public init(
    api: APIClient,
    now: @escaping @Sendable () -> Date,
    items: Shared<IdentifiedArrayOf<WatchlistItem>>,
    state: Shared<SyncState>,
    batchSize: Int = 50,
    maxRounds: Int = 10
  ) {
    self.api = api
    self.now = now
    self.items = items
    self.state = state
    self.batchSize = batchSize
    self.maxRounds = maxRounds
  }

  // MARK: Public

  public func sync() async throws -> SyncReport {
    if let inFlight {
      rerunRequested = true
      joinedCallerCount += 1
      return try await inFlight.value
    }
    let task = Task { try await self.runUntilSettled() }
    inFlight = task
    return try await task.value
  }

  /// Forgets the cursor, acknowledgements and tombstones (used after account deletion). Local items are untouched.
  /// It also bumps `generation`, so a run that is mid-request when the reset happens discards its result instead of
  /// writing the old account's cursor back.
  public func reset() {
    generation += 1
    state.withLock { $0 = .initial }
  }

  // MARK: Internal

  /// The number of callers that joined an in-flight run. Tests use it to order concurrent calls.
  private(set) var joinedCallerCount = 0

  // MARK: Private

  private let api: APIClient
  private let now: @Sendable () -> Date
  private let items: Shared<IdentifiedArrayOf<WatchlistItem>>
  private let state: Shared<SyncState>
  private let batchSize: Int
  private let maxRounds: Int
  private var inFlight: Task<SyncReport, any Error>?
  private var rerunRequested = false
  private var generation = 0

  private static func readableRow(_ dto: WatchlistItemDTO) -> RemoteWatchlistItem? {
    do {
      return try SyncMapping.remote(dto)
    } catch {
      Log.sync.error("Skipping unreadable watchlist row \(dto.symbol): \(error)")
      return nil
    }
  }

  private func runUntilSettled() async throws -> SyncReport {
    // Clearing inFlight inside the task, with no suspension point after the last rerun check, means a caller can't
    // join a run that has already finished.
    defer { inFlight = nil }
    var startGeneration = generation
    var lastPassDiscarded = false
    var total = SyncReport.empty
    repeat {
      rerunRequested = false
      total += try await runRounds()
      lastPassDiscarded = generation != startGeneration
      if lastPassDiscarded {
        // A reset landed mid-pass, so that pass's merge was discarded. Adopt the new generation, and keep looping
        // while `rerunRequested`, so a sync that was requested after the reset still runs.
        startGeneration = generation
      }
    } while rerunRequested
    guard !lastPassDiscarded else {
      return total
    }
    let finishedAt = now().truncatedToMilliseconds
    state.withLock { $0.lastSyncedAt = finishedAt }
    return total
  }

  private func runRounds() async throws -> SyncReport {
    let skipped = SyncPlanner.unsyncableSymbols(items: items.wrappedValue, state: state.wrappedValue)
    if !skipped.isEmpty {
      Log.sync.error("Keeping \(skipped.joined(separator: ", ")) local-only: symbol not accepted by the sync endpoint")
    }
    var report = SyncReport.empty
    while report.rounds < maxRounds {
      let pending = SyncPlanner.pendingChanges(items: items.wrappedValue, state: state.wrappedValue)
      let batch = Array(pending.prefix(batchSize))
      let sentAt = now()
      let request = SyncRequestDTO(cursor: state.wrappedValue.cursor, changes: batch.map { SyncMapping.changeDTO($0, now: sentAt) })

      let requestGeneration = generation
      let response = try await api.syncWatchlist(request)
      guard generation == requestGeneration else { break }

      let remote = response.changes.compactMap(Self.readableRow)
      let applied = items.withLock { items in
        state.withLock { state in
          let merged = SyncMerger.apply(remote, to: items, state: SyncMerger.acknowledge(batch, in: state))
          items = merged.items
          state = merged.state
          state.cursor = response.cursor
          return merged.applied
        }
      }
      report += SyncReport(pushed: batch.count, pulled: response.changes.count, applied: applied, rounds: 1)

      let stillPending = !SyncPlanner.pendingChanges(items: items.wrappedValue, state: state.wrappedValue).isEmpty
      if !response.hasMore, !stillPending { break }
    }
    return report
  }
}
