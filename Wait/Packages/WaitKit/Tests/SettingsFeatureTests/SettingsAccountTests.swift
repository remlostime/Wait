//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import ComposableArchitecture
import Foundation
@testable import SettingsFeature
import Testing

// MARK: - SettingsAccountTests

@MainActor
@Suite
struct SettingsAccountTests {
  @Test
  func taskShowsTheAnonymousID() async {
    let id = UUID(uuidString: "6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F")!
    let store = TestStore(initialState: SettingsFeature.State(appVersion: "1.0 (1)")) {
      SettingsFeature()
    } withDependencies: {
      $0.identity.anonymousID = { id }
    }
    await store.send(.task)
    await store.receive(\.accountLoaded) { $0.account.anonymousID = id.uuidString }
  }

  @Test
  func deletingAsksForConfirmationThenDeletesAndResetsTheIdentity() async {
    let deleted = LockIsolated(false)
    let resets = LockIsolated(0)
    var state = SettingsFeature.State(appVersion: "1.0 (1)")
    state.account.anonymousID = "OLD"
    let store = TestStore(initialState: state) {
      SettingsFeature()
    } withDependencies: {
      $0.apiClient.deleteAccount = { deleted.setValue(true) }
      $0.identity.reset = { resets.withValue { $0 += 1 } }
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
}
