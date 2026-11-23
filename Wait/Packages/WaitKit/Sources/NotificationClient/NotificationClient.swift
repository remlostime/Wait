//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Dependencies
import DependenciesMacros
import Foundation

// MARK: - NotificationAuthorization

public enum NotificationAuthorization: String, Equatable, Sendable {
  case notDetermined
  case denied
  case authorized
  case provisional
  case ephemeral
}

// MARK: - NotificationClient

/// Local-notification permission, APNs registration and push taps.
@DependencyClient
public struct NotificationClient: Sendable {
  public var authorizationStatus: @Sendable () async -> NotificationAuthorization = { .notDetermined }
  public var requestAuthorization: @Sendable () async throws -> Bool
  public var registerForRemoteNotifications: @Sendable () async -> Void
  public var unregisterForRemoteNotifications: @Sendable () async -> Void
  /// Symbols of pushes the user tapped. Single consumer: subscribe once, at launch.
  public var tappedSymbols: @Sendable () -> AsyncStream<String> = { .finished }
}

// MARK: TestDependencyKey

extension NotificationClient: TestDependencyKey {
  public static let testValue = NotificationClient()
}

extension DependencyValues {
  public var notifications: NotificationClient {
    get { self[NotificationClient.self] }
    set { self[NotificationClient.self] = newValue }
  }
}
