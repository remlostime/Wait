//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import Domain
import Foundation
import IdentifiedCollections
import Persistence
@testable import SyncClient
import Testing

struct SyncMergerTests {
  @Test
  func acknowledgeRecordsTheSentStampForUpsertsAndDeletions() {
    let sent: [SyncChange] = [.upsert(makeItem("AAPL", updatedAt: stamp(1))), .deletion(symbol: "MSFT", at: stamp(2))]
    let state = SyncMerger.acknowledge(sent, in: SyncState(acknowledged: ["NVDA": stamp(0)]))
    #expect(state.acknowledged == ["AAPL": stamp(1), "MSFT": stamp(2), "NVDA": stamp(0)])
  }

  @Test
  func insertsANewRemoteItem() {
    let incoming = makeItem("NVDA", memo: "from B", updatedAt: stamp(5))
    let result = SyncMerger.apply([remote(incoming)], to: [], state: .initial)
    #expect(result.items[id: "NVDA"]?.memo == "from B")
    #expect(result.state.acknowledged["NVDA"] == stamp(5))
    #expect(result.applied == 1)
  }

  @Test
  func replacesAnOlderLocalItemButKeepsItsCreatedAt() {
    var local = makeItem("AAPL", memo: "old", updatedAt: stamp(1))
    local.createdAt = stamp(-1000)
    let result = SyncMerger.apply([remote(makeItem("AAPL", memo: "new", updatedAt: stamp(2)))], to: [local], state: .initial)
    #expect(result.items[id: "AAPL"]?.memo == "new")
    #expect(result.items[id: "AAPL"]?.createdAt == stamp(-1000))
    #expect(result.applied == 1)
  }

  @Test
  func acknowledgesAnIdenticalEchoWithoutCountingIt() {
    let local = makeItem("AAPL", memo: "same", updatedAt: stamp(3))
    let result = SyncMerger.apply([remote(local)], to: [local], state: .initial)
    #expect(result.items == [local])
    #expect(result.state.acknowledged["AAPL"] == stamp(3))
    #expect(result.applied == 0)
  }

  @Test
  func tieAppliesTheRemoteContent() {
    let local = makeItem("AAPL", memo: "device A", updatedAt: stamp(3))
    let result = SyncMerger.apply([remote(makeItem("AAPL", memo: "server", updatedAt: stamp(3)))], to: [local], state: .initial)
    #expect(result.items[id: "AAPL"]?.memo == "server")
    #expect(result.applied == 0)
  }

  @Test
  func keepsANewerLocalItemPending() {
    let local = makeItem("AAPL", memo: "newer", updatedAt: stamp(9))
    let state = SyncState(acknowledged: ["AAPL": stamp(4)])
    let result = SyncMerger.apply([remote(makeItem("AAPL", memo: "older", updatedAt: stamp(4)))], to: [local], state: state)
    #expect(result.items == [local])
    #expect(result.state.acknowledged["AAPL"] == stamp(4))
    #expect(SyncPlanner.pendingChanges(items: result.items, state: result.state).map(\.symbol) == ["AAPL"])
  }

  @Test
  func deletesWhenTheRemoteTombstoneIsNewer() {
    let local = makeItem("AAPL", updatedAt: stamp(1))
    let result = SyncMerger.apply([remote(makeItem("AAPL", updatedAt: stamp(2)), deleted: true)], to: [local], state: .initial)
    #expect(result.items.isEmpty)
    #expect(result.state.tombstones["AAPL"] == stamp(2))
    #expect(result.state.acknowledged["AAPL"] == stamp(2))
    #expect(result.applied == 1)
  }

  @Test
  func ignoresARemoteTombstoneForAnUnknownSymbol() {
    let result = SyncMerger.apply([remote(makeItem("TSLA", updatedAt: stamp(2)), deleted: true)], to: [], state: .initial)
    #expect(result.items.isEmpty)
    #expect(result.state == .initial)
  }

  @Test
  func keepsALocalItemNewerThanARemoteTombstone() {
    let local = makeItem("AAPL", updatedAt: stamp(5))
    let result = SyncMerger.apply([remote(makeItem("AAPL", updatedAt: stamp(2)), deleted: true)], to: [local], state: .initial)
    #expect(result.items == [local])
  }

  @Test
  func resurrectsWhenTheRemoteItemIsNewerThanTheLocalTombstone() {
    let state = SyncState(tombstones: ["AAPL": stamp(2)])
    let result = SyncMerger.apply([remote(makeItem("AAPL", memo: "back", updatedAt: stamp(3)))], to: [], state: state)
    #expect(result.items[id: "AAPL"]?.memo == "back")
    #expect(result.state.tombstones["AAPL"] == nil)
  }

  @Test
  func adoptsTheServerStampWhenAnIdenticalEchoComesBackClamped() {
    let local = makeItem("AAPL", memo: "same", updatedAt: stamp(9_000_000))
    let echo = makeItem("AAPL", memo: "same", updatedAt: stamp(300_000))
    let result = SyncMerger.apply([remote(echo)], to: [local], state: SyncState(acknowledged: ["AAPL": stamp(9_000_000)]))
    #expect(result.items[id: "AAPL"]?.updatedAt == stamp(300_000))
    #expect(result.state.acknowledged["AAPL"] == stamp(300_000))
    #expect(result.applied == 0)
    #expect(SyncPlanner.pendingChanges(items: result.items, state: result.state).isEmpty)
  }

  @Test
  func adoptsTheServerStampForAClampedTombstoneEcho() {
    let state = SyncState(acknowledged: ["AAPL": stamp(9_000_000)], tombstones: ["AAPL": stamp(9_000_000)])
    let result = SyncMerger.apply([remote(makeItem("AAPL", updatedAt: stamp(300_000)), deleted: true)], to: [], state: state)
    #expect(result.state.tombstones["AAPL"] == stamp(300_000))
    #expect(result.state.acknowledged["AAPL"] == stamp(300_000))
  }

  @Test
  func staysDeletedWhenTheLocalTombstoneIsNewer() {
    let state = SyncState(tombstones: ["AAPL": stamp(5)])
    let result = SyncMerger.apply([remote(makeItem("AAPL", updatedAt: stamp(3)))], to: [], state: state)
    #expect(result.items.isEmpty)
    #expect(result.state.tombstones["AAPL"] == stamp(5))
  }

  /// What the server stores and sends back for `local`, uploaded when the device clock read `sentAt`.
  private func serverEcho(of local: WatchlistItem, sentAt: Date, version: Int = 1) throws -> RemoteWatchlistItem {
    let wire = SyncMapping.changeDTO(.upsert(local), now: sentAt)
    return try SyncMapping.remote(SyncMapping.itemDTO(from: wire, version: version))
  }

  @Test
  func anEchoOfALongMemoKeepsTheFullLocalMemoAndAcknowledgesIt() throws {
    let longMemo = String(repeating: "m", count: 12_000)
    let local = makeItem("AAPL", memo: longMemo, updatedAt: stamp(3))
    let echo = try serverEcho(of: local, sentAt: stamp(3))
    #expect(echo.item.memo.utf16.count == 10_000)

    // Same stamp (a tie) and the clamped copy: the local content still wins, because it is our own echo.
    let result = SyncMerger.apply([echo], to: [local], state: SyncState(acknowledged: ["AAPL": stamp(3)]))

    #expect(result.items[id: "AAPL"]?.memo == longMemo)
    #expect(result.items[id: "AAPL"]?.updatedAt == stamp(3))
    #expect(result.state.acknowledged["AAPL"] == stamp(3))
    #expect(result.applied == 0)
    #expect(SyncPlanner.pendingChanges(items: result.items, state: result.state).isEmpty)
  }

  @Test
  func anEchoWithAClampedStampAndRoundedAnchorsStillAdoptsTheServerStamp() throws {
    var local = makeItem("AAPL", memo: String(repeating: "m", count: 12_000), updatedAt: stamp(9_000_000))
    local.ladder = try PriceLadder(buyLow: Decimal(string: "1.23456789")!, buyHigh: 5)
    // The device clock is at stamp(0), so the stamp goes out as stamp(300_000), and the anchor is rounded to 1.234568.
    let echo = try serverEcho(of: local, sentAt: stamp(0))
    #expect(echo.stamp == stamp(300_000))
    #expect(echo.item.ladder != local.ladder)

    let result = SyncMerger.apply([echo], to: [local], state: SyncState(acknowledged: ["AAPL": stamp(9_000_000)]))

    #expect(result.items[id: "AAPL"]?.updatedAt == stamp(300_000))
    #expect(result.items[id: "AAPL"]?.memo.utf16.count == 12_000)
    #expect(result.items[id: "AAPL"]?.ladder == local.ladder)
    #expect(result.state.acknowledged["AAPL"] == stamp(300_000))
    #expect(result.applied == 0)
    #expect(SyncPlanner.pendingChanges(items: result.items, state: result.state).isEmpty)
  }

  @Test
  func anEchoOfAnItemWithOutOfRangeSortIndexAndHistoryKeepsTheLocalValues() throws {
    var local = makeItem("AAPL", sortIndex: 5_000_000, updatedAt: stamp(3))
    local.ladderHistory = [LadderRevision(date: Date(timeIntervalSince1970: -5), ladder: .empty)]
    let result = SyncMerger.apply([try serverEcho(of: local, sentAt: stamp(3))], to: [local], state: .initial)
    #expect(result.items == [local])
    #expect(result.applied == 0)
  }

  @Test
  func aTieWithDifferentContentStillAppliesTheServerRowEvenWhenTheLocalMemoIsLong() {
    let local = makeItem("AAPL", memo: String(repeating: "m", count: 12_000), updatedAt: stamp(3))
    let result = SyncMerger.apply([remote(makeItem("AAPL", memo: "from B", updatedAt: stamp(3)))], to: [local], state: .initial)
    #expect(result.items[id: "AAPL"]?.memo == "from B")
  }

  @Test
  func anEchoNewerThanALocalTombstoneClearsIt() {
    let local = makeItem("AAPL", memo: "same", updatedAt: stamp(5))
    let state = SyncState(tombstones: ["AAPL": stamp(2)])
    let result = SyncMerger.apply([remote(local)], to: [local], state: state)
    #expect(result.state.tombstones["AAPL"] == nil)
  }
}
