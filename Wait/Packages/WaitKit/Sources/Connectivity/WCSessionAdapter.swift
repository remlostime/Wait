//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - SessionEvent

public enum SessionEvent: Equatable, Sendable {
  /// The session finished activating and can send and receive.
  case activated
  /// The counterpart app was installed or removed, or the iPhone was paired with another watch.
  case counterpartChanged
  /// A new application context arrived. The payload is the value stored under `SnapshotCoding.contextKey`.
  case receivedContext(Data)
}

// MARK: - WCSessionAdapter

/// The part of `WCSession` that `ConnectivityEngine` needs. The live type is `LiveWCSessionAdapter`; tests use a fake.
public protocol WCSessionAdapter: AnyObject, Sendable {
  var isSupported: Bool { get }
  var isActivated: Bool { get }
  /// iOS: a watch is paired and the watch app is installed. watchOS: the companion iPhone app is installed.
  var canSendToCounterpart: Bool { get }
  /// The snapshot payload of the most recent application context received from the counterpart, if any.
  var receivedContextData: Data? { get }
  /// Activates the session. `onEvent` may be called on any thread.
  func activate(onEvent: @escaping @Sendable (SessionEvent) -> Void)
  /// Replaces the application context with `[SnapshotCoding.contextKey: data]`.
  func updateContext(_ data: Data) throws
}
