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
/// - Sends are serialized. One flush at a time reads the pending payload, sends it, and clears it only if no
///   newer one arrived meanwhile, so an older payload can never be handed to the session after a newer one.
/// - The last payload that was handed to the session successfully is kept. It is sent again when the session
///   re-activates or the counterpart changes (for example the user switches watches) and nothing newer is pending.
/// - Receiving is latest-wins by `generatedAt`. A context older than, or equal to, the latest one is ignored.
/// - Every stream from `snapshots()` first yields the latest snapshot already known (including the
///   context received before launch), then each newer one.
///
/// State sits behind a lock and events are handled synchronously, so delivery order is deterministic.
/// The state lock is never held across a call into the session; `flushLock` serializes those calls instead.
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
    continuation.onTermination = { [weak self] _ in
      self?.removeContinuation(id: id)
    }
    // Register and replay in one critical section: `deliver` yields under the same lock, so the replayed
    // value is always yielded before any newer one.
    state.withLock { locked in
      locked.continuations[id] = continuation
      if let latest = locked.latestReceived {
        continuation.yield(latest)
      }
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
        flush(resendingLastSent: true)
      case .counterpartChanged:
        flush(resendingLastSent: true)
      case let .receivedContext(data):
        deliver(data)
    }
  }

  // MARK: Private

  private struct State: Sendable {
    var didRequestActivation = false
    var pending: Data?
    var lastSent: Data?
    var latestReceived: WatchlistSnapshot?
    var continuations: [UUID: AsyncStream<WatchlistSnapshot>.Continuation] = [:]
  }

  private static let logger = Logger(subsystem: "com.chenkai.wait", category: "connectivity")

  private let adapter: any WCSessionAdapter
  private let maxContextBytes: Int
  private let state = OSAllocatedUnfairLock(initialState: State())
  /// Held for a whole flush (read pending, send, clear). Never taken while holding `state`.
  private let flushLock = NSLock()

  /// Sends the pending payload, or, when `resendingLastSent` and nothing is pending, the last one that was sent.
  private func flush(resendingLastSent: Bool = false) {
    flushLock.withLock {
      guard adapter.isActivated, adapter.canSendToCounterpart else {
        return
      }
      let data = state.withLock { locked in locked.pending ?? (resendingLastSent ? locked.lastSent : nil) }
      guard let data else {
        return
      }
      do {
        try adapter.updateContext(data)
        state.withLock { locked in
          if locked.pending == data {
            locked.pending = nil
          }
          locked.lastSent = data
        }
      } catch {
        Self.logger.error("updateApplicationContext failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  private func deliver(_ data: Data) {
    guard let snapshot = SnapshotCoding.decode(data) else {
      Self.logger.error("Dropped an application context that is not a WatchlistSnapshot")
      return
    }
    // Yield under the lock so two deliveries (or a delivery and a new subscriber) cannot be reordered.
    // `yield` on a buffered stream never blocks and never calls `onTermination` synchronously.
    state.withLock { locked in
      if let current = locked.latestReceived, snapshot.generatedAt < current.generatedAt || snapshot == current {
        return
      }
      locked.latestReceived = snapshot
      for continuation in locked.continuations.values {
        continuation.yield(snapshot)
      }
    }
  }

  private func removeContinuation(id: UUID) {
    state.withLock { _ = $0.continuations.removeValue(forKey: id) }
  }
}
