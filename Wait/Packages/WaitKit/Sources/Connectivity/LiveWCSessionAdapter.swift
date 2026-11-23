//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import os
@preconcurrency import WatchConnectivity

// MARK: - LiveWCSessionAdapter

/// Wraps `WCSession.default`.
///
/// WCSession calls its delegate on a private background queue. The only mutable state here is the
/// event handler, and it sits behind a lock. The delegate methods stay nonisolated and only forward
/// `Sendable` values, so the Swift 6 checker is satisfied without hopping to the main actor.
final class LiveWCSessionAdapter: NSObject, WCSessionAdapter, @unchecked Sendable {
  // MARK: Lifecycle

  override init() {
    session = WCSession.isSupported() ? WCSession.default : nil
    super.init()
  }

  // MARK: Internal

  static let shared = LiveWCSessionAdapter()

  var isSupported: Bool {
    session != nil
  }

  var isActivated: Bool {
    session?.activationState == .activated
  }

  var canSendToCounterpart: Bool {
    guard let session, session.activationState == .activated else {
      return false
    }
    #if os(watchOS)
      return session.isCompanionAppInstalled
    #else
      return session.isPaired && session.isWatchAppInstalled
    #endif
  }

  var receivedContextData: Data? {
    session?.receivedApplicationContext[SnapshotCoding.contextKey] as? Data
  }

  func activate(onEvent: @escaping @Sendable (SessionEvent) -> Void) {
    guard let session else {
      return
    }
    handler.withLock { $0 = onEvent }
    session.delegate = self
    session.activate()
  }

  func updateContext(_ data: Data) throws {
    guard let session else {
      throw ConnectivityError.unsupported
    }
    try session.updateApplicationContext([SnapshotCoding.contextKey: data])
  }

  // MARK: Private

  private static let logger = Logger(subsystem: "com.chenkai.wait", category: "connectivity")

  private let session: WCSession?
  private let handler = OSAllocatedUnfairLock<(@Sendable (SessionEvent) -> Void)?>(initialState: nil)

  private func emit(_ event: SessionEvent) {
    let onEvent = handler.withLock { $0 }
    onEvent?(event)
  }
}

// MARK: WCSessionDelegate

extension LiveWCSessionAdapter: WCSessionDelegate {
  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
    if let error {
      Self.logger.error("WCSession activation failed: \(error.localizedDescription, privacy: .public)")
    }
    if activationState == .activated {
      emit(.activated)
    }
  }

  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    guard let data = applicationContext[SnapshotCoding.contextKey] as? Data else {
      return
    }
    emit(.receivedContext(data))
  }

  #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
      // The user switched to another watch. Reactivate so the new watch gets the next context.
      session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
      emit(.counterpartChanged)
    }
  #endif

  #if os(watchOS)
    func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
      emit(.counterpartChanged)
    }
  #endif
}
