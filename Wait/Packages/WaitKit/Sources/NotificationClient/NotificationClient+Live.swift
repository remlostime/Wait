//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

#if os(iOS)
import Dependencies
import Logging
import UIKit
import UserNotifications

// MARK: - NotificationCenterDelegate

/// Receives taps and foreground presentations. Installed in `application(_:didFinishLaunchingWithOptions:)`
/// so cold-start taps are not lost; taps are buffered until `AppFeature` subscribes.
final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
  // MARK: Lifecycle

  override init() {
    let (stream, streamContinuation) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .bufferingNewest(8))
    taps = stream
    continuation = streamContinuation
    super.init()
  }

  // MARK: Internal

  static let shared = NotificationCenterDelegate()

  let taps: AsyncStream<String>

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound]
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
    guard let symbol = NotificationPayload.symbol(from: response.notification.request.content.userInfo) else {
      Log.push.info("Ignoring a tapped push without a valid symbol")
      return
    }
    continuation.yield(symbol)
  }

  // MARK: Private

  private let continuation: AsyncStream<String>.Continuation
}

// MARK: - NotificationClient + DependencyKey

extension NotificationClient: DependencyKey {
  public static let liveValue = NotificationClient(
    authorizationStatus: {
      let settings = await UNUserNotificationCenter.current().notificationSettings()
      return NotificationAuthorization(settings.authorizationStatus)
    },
    requestAuthorization: {
      try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    },
    registerForRemoteNotifications: {
      await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
    },
    unregisterForRemoteNotifications: {
      await MainActor.run { UIApplication.shared.unregisterForRemoteNotifications() }
    },
    tappedSymbols: { NotificationCenterDelegate.shared.taps }
  )

  /// Call synchronously from `application(_:didFinishLaunchingWithOptions:)`.
  @MainActor
  public static func installDelegate() {
    UNUserNotificationCenter.current().delegate = NotificationCenterDelegate.shared
  }
}

// MARK: - NotificationAuthorization + UNAuthorizationStatus

extension NotificationAuthorization {
  init(_ status: UNAuthorizationStatus) {
    switch status {
      case .notDetermined:
        self = .notDetermined
      case .denied:
        self = .denied
      case .authorized:
        self = .authorized
      case .provisional:
        self = .provisional
      case .ephemeral:
        self = .ephemeral
      @unknown default:
        self = .notDetermined
    }
  }
}
#endif
