//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Dependencies
import DependenciesTestSupport
import Domain
import Foundation
import IdentifiedCollections
import Persistence
import Sharing
import Testing

// MARK: - SyncStateTests

@Suite(.dependencies { $0.defaultFileStorage = .inMemory })
struct SyncStateTests {
  // MARK: Internal

  @Test
  func removeRecordsTombstoneTruncatedToMilliseconds() {
    @Shared(.watchlist) var items
    @Shared(.syncState) var syncState
    $items.add(item("AAPL"), now: now)

    $items.remove("AAPL", now: now)

    #expect(syncState.tombstones["AAPL"] == now.truncatedToMilliseconds)
    #expect(items[id: "AAPL"] == nil)
  }

  @Test
  func removeOfUnknownSymbolRecordsNothing() {
    @Shared(.watchlist) var items
    @Shared(.syncState) var syncState

    $items.remove("TSLA", now: now)

    #expect(syncState.tombstones.isEmpty)
  }

  @Test
  func addClearsTombstone() {
    @Shared(.watchlist) var items
    @Shared(.syncState) var syncState
    $items.add(item("AAPL"), now: now)
    $items.remove("AAPL", now: now)

    $items.add(item("AAPL"), now: now.addingTimeInterval(60))

    #expect(syncState.tombstones["AAPL"] == nil)
    #expect(items[id: "AAPL"] != nil)
  }

  @Test
  func decodesEmptyObjectAsInitial() throws {
    let state = try JSONDecoder().decode(SyncState.self, from: Data("{}".utf8))
    #expect(state == .initial)
  }

  @Test
  func roundTripsThroughJSON() throws {
    let state = SyncState(
      cursor: "3:AAPL",
      acknowledged: ["AAPL": now.truncatedToMilliseconds],
      tombstones: ["MSFT": now.truncatedToMilliseconds],
      lastSyncedAt: now.truncatedToMilliseconds
    )
    let decoded = try JSONDecoder().decode(SyncState.self, from: JSONEncoder().encode(state))
    #expect(decoded == state)
  }

  // MARK: Private

  private let now = Date(timeIntervalSince1970: 1_795_186_800.123_456)

  private func item(_ symbol: String) -> WatchlistItem {
    WatchlistItem(
      symbol: symbol,
      name: "\(symbol) Inc.",
      ladder: .empty,
      memo: "",
      isFavorite: false,
      sortIndex: 0,
      checklist: [],
      ladderHistory: [],
      createdAt: now,
      updatedAt: now
    )
  }
}
