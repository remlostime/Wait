//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import IdentifiedCollections
import Persistence
@testable import SyncClient
import Testing

struct SyncPlannerTests {
  @Test
  func firstSyncUploadsEveryItemOldestFirst() {
    let items: IdentifiedArrayOf<WatchlistItem> = [makeItem("MSFT", updatedAt: stamp(2)), makeItem("AAPL", updatedAt: stamp(1))]
    let pending = SyncPlanner.pendingChanges(items: items, state: .initial)
    #expect(pending.map(\.symbol) == ["AAPL", "MSFT"])
    #expect(pending.allSatisfy { !$0.isDeletion })
  }

  @Test
  func sortsEqualStampsBySymbol() {
    let items: IdentifiedArrayOf<WatchlistItem> = [makeItem("NVDA"), makeItem("AAPL")]
    #expect(SyncPlanner.pendingChanges(items: items, state: .initial).map(\.symbol) == ["AAPL", "NVDA"])
  }

  @Test
  func skipsItemsAcknowledgedAtTheSameMillisecond() {
    let items: IdentifiedArrayOf<WatchlistItem> = [makeItem("AAPL", updatedAt: stamp(5))]
    let noisy = Date(timeIntervalSince1970: stamp(5).timeIntervalSince1970.nextUp)
    let state = SyncState(acknowledged: ["AAPL": noisy])
    #expect(SyncPlanner.pendingChanges(items: items, state: state).isEmpty)
  }

  @Test
  func includesItemsEditedAfterTheirAcknowledgement() {
    let items: IdentifiedArrayOf<WatchlistItem> = [makeItem("AAPL", updatedAt: stamp(9))]
    let state = SyncState(acknowledged: ["AAPL": stamp(5)])
    #expect(SyncPlanner.pendingChanges(items: items, state: state).map(\.stamp) == [stamp(9)])
  }

  @Test
  func includesUnacknowledgedTombstonesOnly() {
    let state = SyncState(acknowledged: ["MSFT": stamp(3)], tombstones: ["AAPL": stamp(4), "MSFT": stamp(3)])
    let pending = SyncPlanner.pendingChanges(items: [], state: state)
    #expect(pending == [.deletion(symbol: "AAPL", at: stamp(4))])
  }

  @Test
  func leavesSymbolsTheServerWouldRejectLocalOnly() {
    let items: IdentifiedArrayOf<WatchlistItem> = [makeItem("AAPL"), makeItem("BRK B"), makeItem("ÄPPLE"), makeItem("0700.HK")]
    let state = SyncState(tombstones: ["bad symbol": stamp(1)])
    #expect(SyncPlanner.pendingChanges(items: items, state: state).map(\.symbol) == ["0700.HK", "AAPL"])
    #expect(SyncPlanner.unsyncableSymbols(items: items, state: state) == ["BRK B", "bad symbol", "ÄPPLE"])
    #expect(SyncPlanner.isSyncable("BRK.B"))
    #expect(!SyncPlanner.isSyncable(""))
  }

  @Test
  func newerItemWinsOverOlderTombstoneAndViceVersa() {
    let items: IdentifiedArrayOf<WatchlistItem> = [makeItem("AAPL", updatedAt: stamp(10)), makeItem("MSFT", updatedAt: stamp(1))]
    let state = SyncState(tombstones: ["AAPL": stamp(5), "MSFT": stamp(6)])
    let pending = SyncPlanner.pendingChanges(items: items, state: state)
    #expect(pending == [.deletion(symbol: "MSFT", at: stamp(6)), .upsert(items[id: "AAPL"]!)])
  }
}
