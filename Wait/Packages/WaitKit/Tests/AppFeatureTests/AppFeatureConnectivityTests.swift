//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Connectivity
import DependenciesTestSupport
import Domain
import Foundation
import NotificationClient
import Persistence
import Testing
@testable import AppFeature

// MARK: - CallLog

private actor CallLog {
  private(set) var entries: [String] = []

  func append(_ entry: String) {
    entries.append(entry)
  }
}

// MARK: - AppFeatureConnectivityTests

@MainActor
@Suite(.dependencies { $0.defaultFileStorage = .inMemory })
struct AppFeatureConnectivityTests {
  // MARK: Internal

  @Test
  func alsoSendingPublishesLocallyThenSendsToTheWatch() async {
    let log = CallLog()
    var base = SnapshotClient()
    base.publish = { _ in await log.append("publish") }
    var connectivity = ConnectivityClient.noop
    connectivity.send = { _ in await log.append("send") }

    await base.alsoSending(to: connectivity).publish(snapshot)

    #expect(await log.entries == ["publish", "send"])
  }

  @Test
  func aWatchDeliveryErrorDoesNotFailPublishing() async {
    let log = CallLog()
    var base = SnapshotClient()
    base.publish = { _ in await log.append("publish") }
    var connectivity = ConnectivityClient.noop
    connectivity.send = { _ in throw ConnectivityError.unsupported }

    await base.alsoSending(to: connectivity).publish(snapshot)

    #expect(await log.entries == ["publish"])
  }

  @Test(.timeLimit(.minutes(1)))
  func didFinishLaunchingActivatesConnectivity() async {
    let (activations, activationContinuation) = AsyncStream.makeStream(of: Void.self)
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.connectivity = .noop
      $0.connectivity.activate = { activationContinuation.yield() }
      $0.notifications = .noop
      $0.snapshotClient.publish = { _ in }
      $0.continuousClock = ImmediateClock()
      $0.date.now = Date(timeIntervalSince1970: 1_763_800_000)
    }
    store.exhaustivity = .off

    await store.send(.appDelegate(.didFinishLaunching))

    var iterator = activations.makeAsyncIterator()
    let activated: Void? = await iterator.next()
    #expect(activated != nil)
    // `strict: false`: the effects may already have finished, which is not a failure here.
    await store.skipInFlightEffects(strict: false)
  }

  // MARK: Private

  private let snapshot = WatchlistSnapshot(generatedAt: Date(timeIntervalSince1970: 1_763_800_000), quotesAsOf: nil, rows: [])
}
