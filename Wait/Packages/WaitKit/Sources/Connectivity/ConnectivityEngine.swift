//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import os

// MARK: - ConnectivityEngine

/// Runs this process's side of the phone–watch conversation.
///
/// - Sending is latest-wins. `send` keeps only the newest payload and delivers it once the session
///   is activated and the counterpart app is installed. Older payloads that were never delivered are dropped.
/// - Receiving is latest-wins by `generatedAt`. A context older than, or equal to, the latest one is ignored.
/// - Every stream from `snapshots()` first yields the latest snapshot already known (including the
///   context received before launch), then each newer one.
///
/// State sits behind a lock and events are handled synchronously, so delivery order is deterministic.
public final class ConnectivityEngine: Sendable {
  // MARK: Lifecycle

  public init(adapter: any WCSessionAdapter, maxContextBytes: Int = SnapshotCoding.defaultMaxBytes) {
    self.adapter = adapter
    self.maxContextBytes = maxContextBytes
  }

  // MARK: Public

  public func activate() {
    guard adapter.isSupported else {
      return
    }
    let isFirstRequest = state.withLock { locked -> Bool in
      guard !locked.didRequestActivation else {
        return false
      }
      locked.didRequestActivation = true
      return true
    }
    guard isFirstRequest else {
      return
    }
    adapter.activate { [weak self] event in
      self?.handle(event)
    }
  }

  public func send(_ snapshot: WatchlistSnapshot) throws {
    let data = try SnapshotCoding.encode(snapshot, maxBytes: maxContextBytes)
    state.withLock { $0.pending = data }
    flush()
  }

  public func snapshots() -> AsyncStream<WatchlistSnapshot> {
    let (stream, continuation) = AsyncStream.makeStream(of: WatchlistSnapshot.self, bufferingPolicy: .bufferingNewest(1))
    let id = UUID()
    let latest = state.withLock { locked -> WatchlistSnapshot? in
      locked.continuations[id] = continuation
      return locked.latestReceived
    }
    if let latest {
      continuation.yield(latest)
    }
    continuation.onTermination = { [weak self] _ in
      self?.removeContinuation(id: id)
    }
    return stream
  }

  // MARK: Internal

  func handle(_ event: SessionEvent) {
    switch event {
      case .activated:
        if let data = adapter.receivedContextData {
          deliver(data)
        }
        flush()
      case .counterpartChanged:
        flush()
      case let .receivedContext(data):
        deliver(data)
    }
  }

  // MARK: Private

  private struct State: Sendable {
    var didRequestActivation = false
    var pending: Data?
    var latestReceived: WatchlistSnapshot?
    var continuations: [UUID: AsyncStream<WatchlistSnapshot>.Continuation] = [:]
  }

  private static let logger = Logger(subsystem: "com.chenkai.wait", category: "connectivity")

  private let adapter: any WCSessionAdapter
  private let maxContextBytes: Int
  private let state = OSAllocatedUnfairLock(initialState: State())

  private func flush() {
    guard adapter.isActivated, adapter.canSendToCounterpart else {
      return
    }
    guard let data = state.withLock({ $0.pending }) else {
      return
    }
    do {
      try adapter.updateContext(data)
      state.withLock { locked in
        if locked.pending == data {
          locked.pending = nil
        }
      }
    } catch {
      Self.logger.error("updateApplicationContext failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func deliver(_ data: Data) {
    guard let snapshot = SnapshotCoding.decode(data) else {
      Self.logger.error("Dropped an application context that is not a WatchlistSnapshot")
      return
    }
    let continuations = state.withLock { locked -> [AsyncStream<WatchlistSnapshot>.Continuation] in
      if let current = locked.latestReceived, snapshot.generatedAt < current.generatedAt || snapshot == current {
        return []
      }
      locked.latestReceived = snapshot
      return Array(locked.continuations.values)
    }
    for continuation in continuations {
      continuation.yield(snapshot)
    }
  }

  private func removeContinuation(id: UUID) {
    state.withLock { _ = $0.continuations.removeValue(forKey: id) }
  }
}
