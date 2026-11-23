//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import os
@testable import Connectivity

// MARK: - FakeSessionError

enum FakeSessionError: Error, Equatable, Sendable {
  case notReachable
}

// MARK: - FakeSessionAdapter

/// A synchronous stand-in for `WCSession`. Events fire on the calling thread, so tests are deterministic.
final class FakeSessionAdapter: WCSessionAdapter, Sendable {
  // MARK: Lifecycle

  init(_ initial: State = State()) {
    state = OSAllocatedUnfairLock(initialState: initial)
  }

  // MARK: Internal

  struct State: Sendable {
    var isSupported = true
    var isActivated = false
    var canSendToCounterpart = true
    var receivedContextData: Data?
    var activationCount = 0
    var sentContexts: [Data] = []
    var updateError: FakeSessionError?
    var onEvent: (@Sendable (SessionEvent) -> Void)?
  }

  var isSupported: Bool { state.withLock { $0.isSupported } }
  var isActivated: Bool { state.withLock { $0.isActivated } }
  var canSendToCounterpart: Bool { state.withLock { $0.canSendToCounterpart } }
  var receivedContextData: Data? { state.withLock { $0.receivedContextData } }
  var activationCount: Int { state.withLock { $0.activationCount } }
  var sentContexts: [Data] { state.withLock { $0.sentContexts } }

  func activate(onEvent: @escaping @Sendable (SessionEvent) -> Void) {
    state.withLock {
      $0.activationCount += 1
      $0.onEvent = onEvent
    }
  }

  func updateContext(_ data: Data) throws {
    try state.withLock { locked in
      if let error = locked.updateError {
        throw error
      }
      locked.sentContexts.append(data)
    }
  }

  /// Simulates `activationDidCompleteWith: .activated`.
  func completeActivation() {
    let onEvent = state.withLock { locked -> (@Sendable (SessionEvent) -> Void)? in
      locked.isActivated = true
      return locked.onEvent
    }
    onEvent?(.activated)
  }

  /// Simulates `didReceiveApplicationContext`.
  func receive(_ data: Data) {
    let onEvent = state.withLock { locked -> (@Sendable (SessionEvent) -> Void)? in
      locked.receivedContextData = data
      return locked.onEvent
    }
    onEvent?(.receivedContext(data))
  }

  /// Simulates the watch app being installed or removed.
  func setCanSendToCounterpart(_ value: Bool) {
    let onEvent = state.withLock { locked -> (@Sendable (SessionEvent) -> Void)? in
      locked.canSendToCounterpart = value
      return locked.onEvent
    }
    onEvent?(.counterpartChanged)
  }

  func setUpdateError(_ error: FakeSessionError?) {
    state.withLock { $0.updateError = error }
  }

  // MARK: Private

  private let state: OSAllocatedUnfairLock<State>
}
