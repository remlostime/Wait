//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Testing
@testable import Connectivity

// MARK: - WatchSnapshotStoreTests

@MainActor
@Suite
struct WatchSnapshotStoreTests {
  // MARK: Internal

  @Test
  func isEmptyUntilTheFirstSnapshot() {
    let store = WatchSnapshotStore(connectivity: .noop)

    #expect(store.snapshot == nil)
    #expect(store.isEmpty)
    #expect(store.favorites.isEmpty)
    #expect(store.others.isEmpty)
  }

  @Test
  func startActivatesAndAppliesStreamedSnapshots() async throws {
    let first = try SnapshotFixtures.snapshot(rowCount: 2)
    let second = try SnapshotFixtures.snapshot(rowCount: 3, generatedAt: SnapshotFixtures.generatedAt.addingTimeInterval(60))
    let recorder = CallRecorder()
    let store = WatchSnapshotStore(connectivity: client(yielding: [first, second], recorder: recorder))

    await store.start()

    #expect(await recorder.values == ["activate"])
    #expect(store.snapshot == second)
  }

  @Test
  func anOlderSnapshotDoesNotReplaceANewerOne() async throws {
    let newer = try SnapshotFixtures.snapshot(rowCount: 3, generatedAt: SnapshotFixtures.generatedAt.addingTimeInterval(60))
    let older = try SnapshotFixtures.snapshot(rowCount: 1)
    let store = WatchSnapshotStore(connectivity: client(yielding: [newer, older]))

    await store.start()

    #expect(store.snapshot == newer)
  }

  @Test
  func splitsFavoritesFromOthersInSnapshotOrder() async throws {
    let snapshot = WatchlistSnapshot(
      generatedAt: SnapshotFixtures.generatedAt,
      quotesAsOf: nil,
      rows: [
        try SnapshotFixtures.row(0, isFavorite: true),
        try SnapshotFixtures.row(1, isFavorite: false),
        try SnapshotFixtures.row(2, isFavorite: true),
      ]
    )
    let store = WatchSnapshotStore(connectivity: client(yielding: [snapshot]))

    await store.start()

    #expect(store.favorites.map(\.symbol) == ["SYM0", "SYM2"])
    #expect(store.others.map(\.symbol) == ["SYM1"])
    #expect(!store.isEmpty)
  }

  @Test
  func findsARowBySymbol() async throws {
    let store = WatchSnapshotStore(connectivity: client(yielding: [try SnapshotFixtures.snapshot(rowCount: 2)]))

    await store.start()

    #expect(store.row(symbol: "SYM1")?.name == "Company 1 Holdings Incorporated")
    #expect(store.row(symbol: "NOPE") == nil)
  }

  // MARK: Private

  private func client(yielding snapshots: [WatchlistSnapshot], recorder: CallRecorder = CallRecorder()) -> ConnectivityClient {
    let (stream, continuation) = AsyncStream.makeStream(of: WatchlistSnapshot.self)
    for snapshot in snapshots {
      continuation.yield(snapshot)
    }
    continuation.finish()
    return ConnectivityClient(
      activate: { await recorder.record("activate") },
      send: { _ in },
      snapshots: { stream }
    )
  }
}
