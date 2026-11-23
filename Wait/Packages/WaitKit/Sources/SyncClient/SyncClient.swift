//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import Dependencies
import DependenciesMacros
import Domain
import Foundation
import IdentifiedCollections
import Persistence
import Sharing

// MARK: - SyncClient

@DependencyClient
public struct SyncClient: Sendable {
  /// Pushes pending changes and pulls remote ones (overview §8.5). Concurrent calls share one run.
  public var sync: @Sendable () async throws -> SyncReport
  /// Forgets sync bookkeeping after account deletion. The local watchlist is kept and re-uploads under the new identity.
  public var reset: @Sendable () async -> Void
}

// MARK: DependencyKey

extension SyncClient: DependencyKey {
  public static let liveValue: SyncClient = {
    @Dependency(\.apiClient) var apiClient
    let engine = SyncEngine(api: apiClient, now: { Date() }, items: Shared(.watchlist), state: Shared(.syncState))
    return SyncClient(
      sync: { try await engine.sync() },
      reset: { await engine.reset() }
    )
  }()

  public static let testValue = SyncClient()
}

extension DependencyValues {
  public var syncClient: SyncClient {
    get { self[SyncClient.self] }
    set { self[SyncClient.self] = newValue }
  }
}
