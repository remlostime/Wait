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
@testable import AppFeature

// MARK: - PushFeatureTests

@MainActor
@Suite(.dependencies { $0.defaultAppStorage = UserDefaults(suiteName: "PushFeatureTests.\(UUID().uuidString)")! })
struct PushFeatureTests {
  // MARK: Internal

  @Test
  func launchRegistersWhenAlertsAreEnabledAndAuthorized() async {
    let registrations = LockIsolated(0)
    let store = TestStore(initialState: state(alertsEnabled: true)) { PushFeature() } withDependencies: {
      $0.notifications.tappedSymbols = { .finished }
      $0.notifications.authorizationStatus = { .authorized }
      $0.notifications.registerForRemoteNotifications = { registrations.withValue { $0 += 1 } }
    }

    await store.send(.launched)
    await store.receive(\.authorizationLoaded, .authorized)
    await store.finish()
    #expect(registrations.value == 1)
  }

  @Test
  func launchDoesNotRegisterWhenAlertsAreOff() async {
    let store = TestStore(initialState: state(alertsEnabled: false)) { PushFeature() } withDependencies: {
      $0.notifications.tappedSymbols = { .finished }
      $0.notifications.authorizationStatus = { .authorized }
    }

    await store.send(.launched)
    await store.receive(\.authorizationLoaded, .authorized)
    await store.finish()
  }

  @Test
  func launchDoesNotRegisterWhenPermissionWasDenied() async {
    let store = TestStore(initialState: state(alertsEnabled: true)) { PushFeature() } withDependencies: {
      $0.notifications.tappedSymbols = { .finished }
      $0.notifications.authorizationStatus = { .denied }
    }

    await store.send(.launched)
    await store.receive(\.authorizationLoaded, .denied)
    await store.finish()
  }

  @Test
  func launchRetriesAPendingUnregistration() async {
    let deletions = LockIsolated<[String]>([])
    let store = TestStore(initialState: state(alertsEnabled: false, deviceToken: "abc123")) { PushFeature() } withDependencies: {
      $0.notifications.tappedSymbols = { .finished }
      $0.notifications.authorizationStatus = { .authorized }
      $0.apiClient.unregisterDevice = { token in deletions.withValue { $0.append(token) } }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.launched)
    await store.receive(\.staleTokenRemoved, "abc123") { $0.$deviceToken.withLock { $0 = nil } }
    await store.finish()
    #expect(deletions.value == ["abc123"])
  }

  @Test
  func pendingUnregistrationFailureKeepsTheToken() async {
    struct Offline: Error {}
    let store = TestStore(initialState: state(alertsEnabled: false, deviceToken: "abc123")) { PushFeature() } withDependencies: {
      $0.notifications.tappedSymbols = { .finished }
      $0.notifications.authorizationStatus = { .authorized }
      $0.apiClient.unregisterDevice = { _ in throw Offline() }
    }

    await store.send(.launched)
    await store.receive(\.authorizationLoaded, .authorized)
    await store.finish()
    #expect(store.state.deviceToken == "abc123")
  }

  @Test
  func tapAsksTheParentToOpenTheStock() async {
    let store = TestStore(initialState: state(alertsEnabled: false)) { PushFeature() } withDependencies: {
      $0.notifications.tappedSymbols = {
        AsyncStream { continuation in
          continuation.yield("AAPL")
          continuation.finish()
        }
      }
      $0.notifications.authorizationStatus = { .notDetermined }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.launched)
    await store.receive(\.delegate.openStock, "AAPL")
    await store.finish()
  }

  @Test
  func registeredTokenIsStoredAndUploaded() async {
    let uploads = LockIsolated<[DeviceRegistrationDTO]>([])
    let store = TestStore(initialState: state(alertsEnabled: true)) { PushFeature() } withDependencies: {
      $0.apiClient.registerDevice = { registration in uploads.withValue { $0.append(registration) } }
    }

    await store.send(.registered(Data([0xDE, 0xAD, 0xBE, 0xEF]))) {
      $0.$deviceToken.withLock { $0 = "deadbeef" }
    }
    await store.finish()
    #expect(uploads.value == [DeviceRegistrationDTO(token: "deadbeef", environment: .sandbox, bundleId: "com.chenkai.wait")])
  }

  @Test
  func aTokenThatArrivesAfterAlertsWereTurnedOffIsNeitherStoredNorUploaded() async {
    let store = TestStore(initialState: state(alertsEnabled: false)) { PushFeature() }

    // `apiClient.registerDevice` isn't overridden: an upload would report an issue.
    await store.send(.registered(Data([0xDE, 0xAD, 0xBE, 0xEF])))
    await store.finish()
    #expect(store.state.deviceToken == nil)
  }

  @Test
  func aStaleTokenConfirmationKeepsANewerStoredToken() async {
    let store = TestStore(initialState: state(alertsEnabled: true, deviceToken: "new")) { PushFeature() }

    await store.send(.staleTokenRemoved("old"))
    #expect(store.state.deviceToken == "new")
  }

  @Test
  func uploadFailureKeepsTheTokenForTheNextLaunch() async {
    struct Offline: Error {}
    let store = TestStore(initialState: state(alertsEnabled: true)) { PushFeature() } withDependencies: {
      $0.apiClient.registerDevice = { _ in throw Offline() }
    }

    await store.send(.registered(Data([0x01]))) {
      $0.$deviceToken.withLock { $0 = "01" }
    }
    await store.finish()
  }

  @Test
  func registrationFailureChangesNothing() async {
    let store = TestStore(initialState: state(alertsEnabled: true)) { PushFeature() }
    await store.send(.registrationFailed("no valid aps-environment entitlement"))
  }

  // MARK: Private

  private func state(alertsEnabled: Bool, deviceToken: String? = nil) -> PushFeature.State {
    let state = PushFeature.State()
    state.$alertsEnabled.withLock { $0 = alertsEnabled }
    state.$deviceToken.withLock { $0 = deviceToken }
    return state
  }
}
