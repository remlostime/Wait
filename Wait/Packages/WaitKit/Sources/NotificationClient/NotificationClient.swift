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
  /// The URL that opens this app's page in the system Settings app (`UIApplication.openNotificationSettingsURLString`, read on the main actor).
  public var notificationSettingsURL: @Sendable () async -> URL?
  /// Symbols of pushes the user tapped. Every call returns a fresh stream, so a new subscriber never ends another one's stream.
  /// Taps that arrive while nobody is subscribed (a cold start) are kept, up to 8, and go to the next subscriber.
  public var tappedSymbols: @Sendable () -> AsyncStream<String> = { .finished }
}

// MARK: TestDependencyKey

extension NotificationClient: TestDependencyKey {
  public static let testValue = NotificationClient()
}

extension NotificationClient {
  /// Does nothing and reports `.notDetermined`. `@DependencyClient` makes even the endpoints with a default report "Unimplemented"
  /// under test, so a test that reaches the client without caring about it uses this.
  public static let noop = NotificationClient(
    authorizationStatus: { .notDetermined },
    requestAuthorization: { false },
    registerForRemoteNotifications: {},
    notificationSettingsURL: { nil },
    tappedSymbols: { .finished }
  )
}

extension DependencyValues {
  public var notifications: NotificationClient {
    get { self[NotificationClient.self] }
    set { self[NotificationClient.self] = newValue }
  }
}
