//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - TapBroadcaster

/// Fans each tapped symbol out to every current subscriber. Every `stream()` call returns its own stream, so cancelling or
/// finishing one subscriber (a second `.launched` replaces the first consumer) never ends another one's stream.
/// While nobody is subscribed, taps are kept (the newest `bufferLimit`) and handed to the next subscriber, so a cold-start tap
/// that lands before `AppFeature` subscribes is not lost.
final class TapBroadcaster: @unchecked Sendable {
  // MARK: Lifecycle

  init(bufferLimit: Int = 8) {
    self.bufferLimit = bufferLimit
  }

  // MARK: Internal

  func stream() -> AsyncStream<String> {
    let (stream, continuation) = AsyncStream.makeStream(of: String.self)
    let id = UUID()
    continuation.onTermination = { [weak self] _ in
      self?.remove(id)
    }
    lock.lock()
    defer { lock.unlock() }
    for symbol in backlog {
      continuation.yield(symbol)
    }
    backlog.removeAll()
    continuations[id] = continuation
    return stream
  }

  func send(_ symbol: String) {
    lock.lock()
    guard !continuations.isEmpty else {
      backlog.append(symbol)
      if backlog.count > bufferLimit {
        backlog.removeFirst(backlog.count - bufferLimit)
      }
      lock.unlock()
      return
    }
    let subscribers = Array(continuations.values)
    lock.unlock()
    for subscriber in subscribers {
      subscriber.yield(symbol)
    }
  }

  // MARK: Private

  private let bufferLimit: Int
  private let lock = NSLock()
  private var continuations: [UUID: AsyncStream<String>.Continuation] = [:]
  private var backlog: [String] = []

  private func remove(_ id: UUID) {
    lock.lock()
    continuations[id] = nil
    lock.unlock()
  }
}
