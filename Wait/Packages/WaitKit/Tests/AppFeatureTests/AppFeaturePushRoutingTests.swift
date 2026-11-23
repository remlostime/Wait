//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import ComposableArchitecture
import Connectivity
import DependenciesTestSupport
import Foundation
import NotificationClient
import SyncClient
import Testing
@testable import AppFeature

// MARK: - AppFeaturePushRoutingTests

@MainActor
@Suite(.dependencies { $0.defaultAppStorage = UserDefaults(suiteName: "AppFeaturePushRoutingTests.\(UUID().uuidString)")! })
struct AppFeaturePushRoutingTests {
  @Test
  func forwardsTheDeviceTokenToPushFeature() async {
    let state = AppFeature.State()
    // `PushFeature` ignores a token while alerts are off.
    state.push.$alertsEnabled.withLock { $0 = true }
    let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
      $0.apiClient.registerDevice = { _ in }
      $0.connectivity = .noop
      $0.notifications = .noop
      $0.syncClient.sync = { SyncReport() }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.appDelegate(.didRegisterForRemoteNotifications(Data([0x01, 0x02]))))
    await store.receive(\.push.registered, Data([0x01, 0x02]))
    await store.finish()
    #expect(store.state.push.deviceToken == "0102")
  }

  @Test
  func openStockDelegateOpensTheDeepLink() async {
    let store = TestStore(initialState: AppFeature.State()) { AppFeature() } withDependencies: {
      $0.connectivity = .noop
      $0.notifications = .noop
      $0.syncClient.sync = { SyncReport() }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.push(.delegate(.openStock("AAPL"))))
    await store.receive(\.openURL, URL(string: "wait://stock/AAPL")!)
    await store.skipInFlightEffects()
  }
}
