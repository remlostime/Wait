//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import NotificationClient
@testable import SettingsFeature
import SyncClient
import Testing

// MARK: - SettingsAccountTests

@MainActor
@Suite(.dependencies { $0.defaultAppStorage = UserDefaults(suiteName: "SettingsAccountTests.\(UUID().uuidString)")! })
struct SettingsAccountTests {
  @Test
  func taskShowsTheAnonymousID() async {
    let id = UUID(uuidString: "6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F")!
    let store = TestStore(initialState: SettingsFeature.State(appVersion: "1.0 (1)")) {
      SettingsFeature()
    } withDependencies: {
      $0.identity.anonymousID = { id }
      $0.notifications = .noop
    }
    // `.task` also loads the notification status. The two effects run concurrently, so their actions can arrive in either order.
    store.exhaustivity = .off(showSkippedAssertions: false)
    await store.send(.task)
    await store.finish()
    #expect(store.state.account.anonymousID == id.uuidString)
  }

  @Test
  func deletingAsksForConfirmationThenDeletesAndResetsTheIdentity() async {
    let deleted = LockIsolated(false)
    let resets = LockIsolated(0)
    let order = LockIsolated<[String]>([])
    var state = SettingsFeature.State(appVersion: "1.0 (1)")
    state.account.anonymousID = "OLD"
    let store = TestStore(initialState: state) {
      SettingsFeature()
    } withDependencies: {
      $0.apiClient.deleteAccount = {
        deleted.setValue(true)
        order.withValue { $0.append("deleteAccount") }
      }
      $0.identity.reset = {
        resets.withValue { $0 += 1 }
        order.withValue { $0.append("identity.reset") }
      }
      $0.syncClient.reset = { order.withValue { $0.append("syncClient.reset") } }
    }
    await store.send(.deleteAccountTapped) { $0.alert = .deleteAccount }
    await store.send(.alert(.presented(.confirmDeleteAccount))) {
      $0.alert = nil
      $0.account.isDeleting = true
    }
    await store.receive(\.accountDeleted) {
      $0.account.isDeleting = false
      $0.account.anonymousID = nil
    }
    #expect(deleted.value)
    #expect(resets.value == 1)
    // The identity goes before the sync bookkeeping, so no sync can run as the deleted account with the old cursor.
    #expect(order.value == ["deleteAccount", "identity.reset", "syncClient.reset"])
  }

  @Test
  func deletingTheAccountWithAlertsOnRegistersForPushesAgain() async {
    let registrations = LockIsolated(0)
    let store = deletionStore(alertsEnabled: true) { registrations.withValue { $0 += 1 } }

    await store.send(.deleteAccountTapped) { $0.alert = .deleteAccount }
    await store.send(.alert(.presented(.confirmDeleteAccount))) {
      $0.alert = nil
      $0.account.isDeleting = true
    }
    await store.receive(\.accountDeleted) {
      $0.account.isDeleting = false
      $0.account.anonymousID = nil
    }
    await store.finish()
    // The server dropped the device with the account. APNs hands the token back and `PushFeature` uploads it under the new identity.
    #expect(registrations.value == 1)
  }

  @Test
  func deletingTheAccountWithAlertsOffDoesNotRegisterForPushes() async {
    let registrations = LockIsolated(0)
    let store = deletionStore(alertsEnabled: false) { registrations.withValue { $0 += 1 } }

    await store.send(.deleteAccountTapped) { $0.alert = .deleteAccount }
    await store.send(.alert(.presented(.confirmDeleteAccount))) {
      $0.alert = nil
      $0.account.isDeleting = true
    }
    await store.receive(\.accountDeleted) {
      $0.account.isDeleting = false
      $0.account.anonymousID = nil
    }
    await store.finish()
    #expect(registrations.value == 0)
  }

  @Test
  func cancellingTheAlertDeletesNothing() async {
    let store = TestStore(initialState: SettingsFeature.State(appVersion: "1.0 (1)")) { SettingsFeature() }
    await store.send(.deleteAccountTapped) { $0.alert = .deleteAccount }
    await store.send(.alert(.dismiss)) { $0.alert = nil }
  }

  @Test
  func aFailedDeleteKeepsTheIdentityAndShowsWhy() async {
    var state = SettingsFeature.State(appVersion: "1.0 (1)")
    state.account.anonymousID = "OLD"
    let store = TestStore(initialState: state) {
      SettingsFeature()
    } withDependencies: {
      $0.apiClient.deleteAccount = { throw APIError.transport("The Internet connection appears to be offline.") }
    }
    await store.send(.deleteAccountTapped) { $0.alert = .deleteAccount }
    await store.send(.alert(.presented(.confirmDeleteAccount))) {
      $0.alert = nil
      $0.account.isDeleting = true
    }
    await store.receive(\.accountDeletionFailed) {
      $0.account.isDeleting = false
      $0.account.errorMessage = "The Internet connection appears to be offline."
    }
  }

  // MARK: Private

  private func deletionStore(alertsEnabled: Bool, onRegister: @escaping @Sendable () -> Void) -> TestStoreOf<SettingsFeature> {
    var state = SettingsFeature.State(appVersion: "1.0 (1)")
    state.account.anonymousID = "OLD"
    state.$alertsEnabled.withLock { $0 = alertsEnabled }
    return TestStore(initialState: state) {
      SettingsFeature()
    } withDependencies: {
      $0.apiClient.deleteAccount = {}
      $0.identity.reset = {}
      $0.syncClient.reset = {}
      $0.notifications.registerForRemoteNotifications = { onRegister() }
    }
  }
}
