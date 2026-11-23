//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Dependencies
import DependenciesMacros
import Domain
import Foundation

// MARK: - ConnectivityClient

/// Transport for `WatchlistSnapshot` between the phone and the watch.
/// iOS calls `send`, and watchOS consumes `snapshots()`. Both sides call `activate` once at launch.
@DependencyClient
public struct ConnectivityClient: Sendable {
  public var activate: @Sendable () async -> Void
  public var send: @Sendable (_ snapshot: WatchlistSnapshot) async throws -> Void
  public var snapshots: @Sendable () -> AsyncStream<WatchlistSnapshot> = { AsyncStream { $0.finish() } }
}

// MARK: - ConnectivityError

public enum ConnectivityError: Error, Equatable, Sendable {
  case unsupported
}

public extension ConnectivityClient {
  static let noop = ConnectivityClient(
    activate: {},
    send: { _ in },
    snapshots: { AsyncStream { $0.finish() } }
  )

  static func live(engine: ConnectivityEngine) -> ConnectivityClient {
    ConnectivityClient(
      activate: { engine.activate() },
      send: { snapshot in try engine.send(snapshot) },
      snapshots: { engine.snapshots() }
    )
  }
}

// MARK: - ConnectivityClient + DependencyKey

extension ConnectivityClient: DependencyKey {
  public static let liveValue = ConnectivityClient.live(engine: ConnectivityEngine(adapter: LiveWCSessionAdapter.shared))
  public static let previewValue = ConnectivityClient.noop
  public static let testValue = ConnectivityClient()
}

public extension DependencyValues {
  var connectivity: ConnectivityClient {
    get { self[ConnectivityClient.self] }
    set { self[ConnectivityClient.self] = newValue }
  }
}
