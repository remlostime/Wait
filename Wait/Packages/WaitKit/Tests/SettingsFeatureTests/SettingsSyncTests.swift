//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Persistence
@testable import SettingsFeature
import SyncClient
import Testing

@MainActor
@Suite(.dependencies { $0.defaultFileStorage = .inMemory })
struct SettingsSyncTests {
  @Test
  func syncNowShowsProgressThenFinishes() async {
    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    } withDependencies: {
      $0.syncClient.sync = { SyncReport(pushed: 1, pulled: 1, applied: 0, rounds: 1) }
    }

    await store.send(.syncNowTapped) { $0.isSyncing = true }
    await store.receive(\.syncFinished) { $0.isSyncing = false }
  }

  @Test
  func aFailedSyncShowsTheMessage() async {
    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    } withDependencies: {
      $0.syncClient.sync = { throw URLError(.notConnectedToInternet) }
    }

    await store.send(.syncNowTapped) { $0.isSyncing = true }
    await store.receive(\.syncFailed) {
      $0.isSyncing = false
      $0.syncError = URLError(.notConnectedToInternet).localizedDescription
    }
  }

  @Test
  func tappingWhileASyncIsRunningDoesNothing() async {
    var state = SettingsFeature.State()
    state.isSyncing = true
    let store = TestStore(initialState: state) { SettingsFeature() }

    await store.send(.syncNowTapped)
  }

  @Test
  func lastSyncedAtReadsTheSharedSyncState() {
    @Shared(.syncState) var syncState
    $syncState.withLock { $0.lastSyncedAt = Date(timeIntervalSince1970: 1_795_186_800) }

    #expect(SettingsFeature.State().lastSyncedAt == Date(timeIntervalSince1970: 1_795_186_800))
  }

  @Test
  func deletingTheAccountResetsSyncState() async {
    let resets = LockIsolated(0)
    let store = TestStore(initialState: SettingsFeature.State()) {
      SettingsFeature()
    } withDependencies: {
      $0.apiClient.deleteAccount = {}
      $0.identity.reset = {}
      $0.syncClient.reset = { resets.withValue { $0 += 1 } }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.deleteAccountTapped)
    await store.send(.alert(.presented(.confirmDeleteAccount)))
    await store.finish()

    #expect(resets.value == 1)
  }
}
