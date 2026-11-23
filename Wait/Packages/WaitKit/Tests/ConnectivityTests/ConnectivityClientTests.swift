//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Testing
@testable import Connectivity

// MARK: - ConnectivityClientTests

@Suite
struct ConnectivityClientTests {
  @Test
  func liveClientRoutesThroughTheEngine() async throws {
    let fake = FakeSessionAdapter()
    let client = ConnectivityClient.live(engine: ConnectivityEngine(adapter: fake))

    await client.activate()
    fake.completeActivation()
    try await client.send(try SnapshotFixtures.snapshot(rowCount: 1))

    #expect(fake.activationCount == 1)
    #expect(fake.sentContexts.count == 1)
  }

  @Test
  func noopClientFinishesItsStreamImmediately() async {
    var count = 0
    for await _ in ConnectivityClient.noop.snapshots() {
      count += 1
    }

    #expect(count == 0)
  }
}
