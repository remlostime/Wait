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
/// so cold-start taps are not lost; `TapBroadcaster` keeps them until `AppFeature` subscribes.
final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
  // MARK: Internal

  static let shared = NotificationCenterDelegate()

  let taps = TapBroadcaster()

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
    taps.send(symbol)
  }
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
    notificationSettingsURL: {
      await MainActor.run { URL(string: UIApplication.openNotificationSettingsURLString) }
    },
    tappedSymbols: { NotificationCenterDelegate.shared.taps.stream() }
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
