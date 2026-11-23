//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import Dependencies
import Domain
import Foundation
import IdentifiedCollections
import Persistence
import Sharing
@testable import SyncClient
import Testing

// MARK: - Gate

/// Holds the first fake request open until the test calls `open()`.
actor Gate {
  // MARK: Internal

  func wait() async {
    guard !isOpen else {
      return
    }
    await withCheckedContinuation { continuation = $0 }
  }

  func open() {
    isOpen = true
    continuation?.resume()
    continuation = nil
  }

  // MARK: Private

  private var continuation: CheckedContinuation<Void, Never>?
  private var isOpen = false
}

// MARK: - SyncEngineTests

struct SyncEngineTests {
  // MARK: Internal

  @Test
  func firstSyncUploadsEveryItemAndAcknowledgesIt() async throws {
    let requests = LockIsolated<[SyncRequestDTO]>([])
    let (engine, items, state) = makeEngine(items: [makeItem("MSFT", updatedAt: stamp(2)), makeItem("AAPL", updatedAt: stamp(1))]) { request in
      requests.withValue { $0.append(request) }
      return Self.echo(request, version: 1)
    }

    let report = try await engine.sync()

    #expect(requests.value.map(\.cursor) == [nil])
    #expect(requests.value[0].changes.map(\.symbol) == ["AAPL", "MSFT"])
    #expect(report == SyncReport(pushed: 2, pulled: 2, applied: 0, rounds: 1))
    #expect(state.wrappedValue.cursor == "1:MSFT")
    #expect(SyncStamp.same(state.wrappedValue.lastSyncedAt, Self.now))
    #expect(SyncPlanner.pendingChanges(items: items.wrappedValue, state: state.wrappedValue).isEmpty)
  }

  @Test
  func pullsRemoteItemsIntoAnEmptyWatchlist() async throws {
    let row = SyncMapping.itemDTO(from: SyncMapping.changeDTO(.upsert(makeItem("NVDA", memo: "from B", updatedAt: stamp(9))), now: .distantFuture), version: 4)
    let (engine, items, state) = makeEngine { _ in SyncResponseDTO(changes: [row], cursor: "4:NVDA", hasMore: false) }

    let report = try await engine.sync()

    #expect(items.wrappedValue[id: "NVDA"]?.memo == "from B")
    #expect(state.wrappedValue.cursor == "4:NVDA")
    #expect(report == SyncReport(pushed: 0, pulled: 1, applied: 1, rounds: 1))
  }

  @Test
  func keepsPullingWhileTheServerHasMore() async throws {
    let requests = LockIsolated<[SyncRequestDTO]>([])
    let (engine, _, state) = makeEngine { request in
      let count = requests.withValue { $0.append(request); return $0.count }
      return SyncResponseDTO(changes: [], cursor: count == 1 ? "1:A" : "2:B", hasMore: count == 1)
    }

    let report = try await engine.sync()

    #expect(requests.value.map(\.cursor) == [nil, "1:A"])
    #expect(report.rounds == 2)
    #expect(state.wrappedValue.cursor == "2:B")
  }

  @Test
  func stopsAfterMaxRounds() async throws {
    let calls = LockIsolated(0)
    let (engine, _, _) = makeEngine(maxRounds: 3) { _ in
      calls.withValue { $0 += 1 }
      return SyncResponseDTO(changes: [], cursor: "1:A", hasMore: true)
    }

    let report = try await engine.sync()

    #expect(calls.value == 3)
    #expect(report.rounds == 3)
  }

  @Test
  func anEditMadeDuringARequestIsPushedInTheNextRound() async throws {
    let items = Shared(value: IdentifiedArrayOf<WatchlistItem>([makeItem("AAPL", memo: "v1", updatedAt: stamp(1))]))
    let state = Shared(value: SyncState.initial)
    let requests = LockIsolated<[SyncRequestDTO]>([])
    var api = APIClient()
    api.syncWatchlist = { request in
      let count = requests.withValue { $0.append(request); return $0.count }
      if count == 1 {
        items.withLock {
          $0[id: "AAPL"]!.memo = "v2"
          $0[id: "AAPL"]!.updatedAt = stamp(2)
        }
      }
      return Self.echo(request, version: count)
    }
    let engine = SyncEngine(api: api, now: { Self.now }, items: items, state: state)

    let report = try await engine.sync()

    #expect(requests.value.count == 2)
    #expect(requests.value[1].changes.map(\.memo) == ["v2"])
    #expect(requests.value[1].changes.map(\.clientUpdatedAt) == [SyncStamp.string(from: stamp(2))])
    #expect(items.wrappedValue[id: "AAPL"]?.memo == "v2")
    #expect(report.rounds == 2)
  }

  @Test
  func concurrentCallsShareOneRunThatRerunsOnce() async throws {
    let gate = Gate()
    let calls = LockIsolated(0)
    let (engine, _, _) = makeEngine { _ in
      let count = calls.withValue { $0 += 1; return $0 }
      if count == 1 { await gate.wait() }
      return SyncResponseDTO(changes: [], cursor: "0:", hasMore: false)
    }

    async let first = engine.sync()
    while calls.value < 1 { await Task.yield() }
    async let second = engine.sync()
    async let third = engine.sync()
    while await engine.joinedCallerCount < 2 { await Task.yield() }
    await gate.open()
    let reports = try await [first, second, third]

    #expect(calls.value == 2)
    #expect(reports == Array(repeating: SyncReport(rounds: 2), count: 3))
  }

  @Test
  func skipsUnreadableRowsButStillAdvancesTheCursor() async throws {
    var unreadable = SyncMapping.itemDTO(from: SyncMapping.changeDTO(.upsert(makeItem("BAD", updatedAt: stamp(3))), now: .distantFuture), version: 3)
    unreadable.ladder = LadderDTO(buyLow: "20", buyHigh: "10")
    let broken = unreadable
    let good = SyncMapping.itemDTO(from: SyncMapping.changeDTO(.upsert(makeItem("NVDA", updatedAt: stamp(3))), now: .distantFuture), version: 3)
    let (engine, items, state) = makeEngine { _ in SyncResponseDTO(changes: [broken, good], cursor: "3:NVDA", hasMore: false) }

    let report = try await engine.sync()

    #expect(items.wrappedValue.ids.elements == ["NVDA"])
    #expect(state.wrappedValue.cursor == "3:NVDA")
    #expect(report.pulled == 2)
    #expect(report.applied == 1)
  }

  @Test
  func aFailedSyncLeavesStateUntouchedAndTheNextOneRuns() async throws {
    let calls = LockIsolated(0)
    let (engine, _, state) = makeEngine(items: [makeItem("AAPL", updatedAt: stamp(1))]) { request in
      let count = calls.withValue { $0 += 1; return $0 }
      if count == 1 { throw URLError(.notConnectedToInternet) }
      return Self.echo(request, version: 1)
    }

    await #expect(throws: URLError.self) { try await engine.sync() }
    #expect(state.wrappedValue == .initial)

    _ = try await engine.sync()
    #expect(SyncStamp.same(state.wrappedValue.acknowledged["AAPL"], stamp(1)))
  }

  @Test
  func aResetDuringARunDiscardsThatRunsMerge() async throws {
    let gate = Gate()
    let calls = LockIsolated(0)
    let (engine, _, state) = makeEngine(items: [makeItem("AAPL", updatedAt: stamp(1))]) { request in
      calls.withValue { $0 += 1 }
      await gate.wait()
      return Self.echo(request, version: 1)
    }

    async let run = engine.sync()
    while calls.value < 1 { await Task.yield() }
    await engine.reset()
    await gate.open()
    _ = try await run

    #expect(state.wrappedValue == .initial)
  }

  @Test
  func aSyncRequestedAfterAMidRunResetStillRuns() async throws {
    let gate = Gate()
    let calls = LockIsolated(0)
    let (engine, _, state) = makeEngine(items: [makeItem("AAPL", updatedAt: stamp(1))]) { request in
      let count = calls.withValue { $0 += 1; return $0 }
      if count == 1 { await gate.wait() }
      return Self.echo(request, version: count)
    }

    async let first = engine.sync()
    while calls.value < 1 { await Task.yield() }
    await engine.reset()
    async let second = engine.sync()
    while await engine.joinedCallerCount < 1 { await Task.yield() }
    await gate.open()
    _ = try await [first, second]

    #expect(calls.value == 2)
    #expect(state.wrappedValue.cursor == "2:AAPL")
    #expect(SyncStamp.same(state.wrappedValue.acknowledged["AAPL"], stamp(1)))
    #expect(SyncStamp.same(state.wrappedValue.lastSyncedAt, Self.now))
  }

  @Test
  func resetForgetsCursorAndAcknowledgements() async {
    let (engine, _, state) = makeEngine(state: SyncState(cursor: "5:AAPL", acknowledged: ["AAPL": stamp(1)], lastSyncedAt: stamp(2))) { _ in
      SyncResponseDTO(changes: [], cursor: "0:", hasMore: false)
    }

    await engine.reset()

    #expect(state.wrappedValue == .initial)
  }

  // MARK: Private

  private static let now = stamp(60_000)

  /// The server echoing every pushed change back at `version`.
  private static func echo(_ request: SyncRequestDTO, version: Int) -> SyncResponseDTO {
    let rows = request.changes.map { SyncMapping.itemDTO(from: $0, version: version) }
    let cursor = rows.last.map { "\(version):\($0.symbol)" } ?? request.cursor ?? "0:"
    return SyncResponseDTO(changes: rows, cursor: cursor, hasMore: false)
  }

  private func makeEngine(
    items: IdentifiedArrayOf<WatchlistItem> = [],
    state: SyncState = .initial,
    maxRounds: Int = 10,
    handler: @escaping @Sendable (SyncRequestDTO) async throws -> SyncResponseDTO
  ) -> (SyncEngine, Shared<IdentifiedArrayOf<WatchlistItem>>, Shared<SyncState>) {
    let itemsReference = Shared(value: items)
    let stateReference = Shared(value: state)
    // Same style as plan 04's tests: start from the unimplemented client and override only what the test uses.
    var api = APIClient()
    api.syncWatchlist = handler
    let engine = SyncEngine(
      api: api,
      now: { Self.now },
      items: itemsReference,
      state: stateReference,
      maxRounds: maxRounds
    )
    return (engine, itemsReference, stateReference)
  }
}
