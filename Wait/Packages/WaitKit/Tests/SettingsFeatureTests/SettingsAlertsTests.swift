//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import NotificationClient
import Testing
@testable import SettingsFeature

// MARK: - SettingsAlertsTests

@MainActor
@Suite(.dependencies { $0.defaultAppStorage = UserDefaults(suiteName: "SettingsAlertsTests.\(UUID().uuidString)")! })
struct SettingsAlertsTests {
  // MARK: Internal

  @Test
  func enablingAlertsRequestsPermissionThenRegisters() async {
    let registrations = LockIsolated(0)
    let store = TestStore(initialState: SettingsFeature.State()) { SettingsFeature() } withDependencies: {
      $0.notifications.requestAuthorization = { true }
      $0.notifications.authorizationStatus = { .authorized }
      $0.notifications.registerForRemoteNotifications = { registrations.withValue { $0 += 1 } }
    }

    await store.send(.alertsToggled(true))
    await store.receive(\.authorizationStatusLoaded, .authorized) { $0.authorizationStatus = .authorized }
    await store.receive(\.alertsEnablementFinished, true) { $0.$alertsEnabled.withLock { $0 = true } }
    await store.finish()
    #expect(registrations.value == 1)
  }

  @Test
  func deniedPermissionLeavesAlertsOffAndOffersSystemSettings() async {
    let store = TestStore(initialState: SettingsFeature.State()) { SettingsFeature() } withDependencies: {
      $0.notifications.requestAuthorization = { false }
      $0.notifications.authorizationStatus = { .denied }
    }

    await store.send(.alertsToggled(true))
    await store.receive(\.authorizationStatusLoaded, .denied) { $0.authorizationStatus = .denied }
    await store.receive(\.alertsEnablementFinished, false)
    await store.finish()
    #expect(store.state.showsOpenSystemSettings)
  }

  @Test
  func permissionErrorCountsAsDenied() async {
    struct Failure: Error {}
    let store = TestStore(initialState: SettingsFeature.State()) { SettingsFeature() } withDependencies: {
      $0.notifications.requestAuthorization = { throw Failure() }
      $0.notifications.authorizationStatus = { .notDetermined }
    }

    await store.send(.alertsToggled(true))
    await store.receive(\.authorizationStatusLoaded, .notDetermined)
    await store.receive(\.alertsEnablementFinished, false)
    await store.finish()
  }

  @Test
  func disablingAlertsClearsTheTokenOnlyAfterTheServerConfirms() async {
    let serverUnregistrations = LockIsolated<[String]>([])
    // `notifications` isn't overridden: turning alerts off must not call into APNs (no `unregisterForRemoteNotifications`).
    let store = TestStore(initialState: enabledState(token: "abc123")) { SettingsFeature() } withDependencies: {
      $0.apiClient.unregisterDevice = { token in serverUnregistrations.withValue { $0.append(token) } }
    }

    await store.send(.alertsToggled(false)) { $0.$alertsEnabled.withLock { $0 = false } }
    await store.receive(\.deviceUnregistered, "abc123") { $0.$apnsDeviceToken.withLock { $0 = nil } }
    await store.finish()
    #expect(serverUnregistrations.value == ["abc123"])
  }

  @Test
  func aConfirmedUnregistrationKeepsANewerStoredToken() async {
    let store = TestStore(initialState: enabledState(token: "new")) { SettingsFeature() }

    await store.send(.deviceUnregistered("old"))
    #expect(store.state.apnsDeviceToken == "new")
  }

  @Test
  func failedServerUnregistrationKeepsTheTokenForTheLaunchRetry() async {
    struct Offline: Error {}
    let store = TestStore(initialState: enabledState(token: "abc123")) { SettingsFeature() } withDependencies: {
      $0.apiClient.unregisterDevice = { _ in throw Offline() }
    }

    await store.send(.alertsToggled(false)) { $0.$alertsEnabled.withLock { $0 = false } }
    await store.finish()
    #expect(store.state.apnsDeviceToken == "abc123")
  }

  @Test
  func openSystemSettingsOpensTheNotificationSettingsURL() async {
    let opened = LockIsolated<URL?>(nil)
    let store = TestStore(initialState: SettingsFeature.State()) { SettingsFeature() } withDependencies: {
      $0.notifications.notificationSettingsURL = { URL(string: "app-notification-settings") }
      $0.openURL = OpenURLEffect { url in
        opened.setValue(url)
        return true
      }
    }

    await store.send(.openSystemSettingsTapped)
    await store.finish()
    #expect(opened.value == URL(string: "app-notification-settings"))
  }

  @Test
  func openSystemSettingsDoesNothingWithoutAURL() async {
    let opened = LockIsolated(false)
    let store = TestStore(initialState: SettingsFeature.State()) { SettingsFeature() } withDependencies: {
      $0.notifications = .noop
      $0.openURL = OpenURLEffect { _ in
        opened.setValue(true)
        return true
      }
    }

    await store.send(.openSystemSettingsTapped)
    await store.finish()
    #expect(!opened.value)
  }

  @Test
  func becomingActiveReloadsTheAuthorizationStatus() async {
    let store = TestStore(initialState: SettingsFeature.State()) { SettingsFeature() } withDependencies: {
      $0.notifications.authorizationStatus = { .denied }
    }

    await store.send(.sceneBecameActive)
    await store.receive(\.authorizationStatusLoaded, .denied) { $0.authorizationStatus = .denied }
  }

  @Test
  func taskLoadsTheAuthorizationStatus() async {
    let store = TestStore(initialState: SettingsFeature.State()) { SettingsFeature() } withDependencies: {
      $0.notifications.authorizationStatus = { .authorized }
      $0.identity.anonymousID = { UUID() } // plan 04's `.task` loads the account id
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.task)
    await store.receive(\.authorizationStatusLoaded, .authorized) { $0.authorizationStatus = .authorized }
    await store.skipInFlightEffects()
  }

  // MARK: Private

  private func enabledState(token: String) -> SettingsFeature.State {
    let state = SettingsFeature.State()
    state.$alertsEnabled.withLock { $0 = true }
    state.$apnsDeviceToken.withLock { $0 = token }
    return state
  }
}
