//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Testing

// MARK: - WatchlistModelTests

@Suite struct WatchlistModelTests {
  @Test func millisecondTruncationIsIdempotentAndMatchesISOParsing() throws {
    let raw = Date(timeIntervalSince1970: 1_795_186_800.123_9)
    let truncated = raw.truncatedToMilliseconds
    #expect(truncated.millisecondsSince1970 == 1_795_186_800_123)
    #expect(truncated.truncatedToMilliseconds == truncated)
    let parsed = try Date("2026-11-20T15:00:00.123Z", strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    #expect(parsed.isSameMillisecond(as: truncated))
  }

  @Test func initsTruncateDatesToMilliseconds() throws {
    let raw = Date(timeIntervalSince1970: 1_795_186_800.123_9)
    let item = WatchlistItem(symbol: "AAPL", name: "Apple", createdAt: raw, updatedAt: raw)
    #expect(item.createdAt.millisecondsSince1970 == 1_795_186_800_123)
    #expect(item.updatedAt == raw.truncatedToMilliseconds)
    #expect(LadderRevision(date: raw, ladder: .empty).date == raw.truncatedToMilliseconds)
  }

  @Test func symbolIsUppercasedAndDefaultsApply() {
    let item = WatchlistItem(symbol: "aapl", name: "Apple", createdAt: fridayOpen, updatedAt: fridayOpen)
    #expect(item.symbol == "AAPL")
    #expect(item.id == "AAPL")
    #expect(item.ladder.isEmpty)
    #expect(item.memo.isEmpty)
    #expect(!item.isFavorite)
  }

  @Test func itemDecodesWithOnlyASymbol() throws {
    let item = try JSONDecoder().decode(WatchlistItem.self, from: Data(#"{"symbol":"msft"}"#.utf8))
    #expect(item.symbol == "MSFT")
    #expect(item.name == "MSFT")
    #expect(item.checklist.isEmpty)
  }

  @Test func itemRoundTrips() throws {
    let item = try WatchlistItem(
      symbol: "PINS",
      name: "Pinterest",
      ladder: PriceLadder(buyLow: 12, buyHigh: 16, fair: 23, trim: 33),
      memo: "line 1\nline 2",
      isFavorite: true,
      sortIndex: 3,
      checklist: [ChecklistItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Wait 30 min", isChecked: true)],
      ladderHistory: [LadderRevision(date: fridayOpen, ladder: PriceLadder(buyHigh: 16))],
      createdAt: fridayOpen,
      updatedAt: fridayOpen
    )
    #expect(try JSONDecoder().decode(WatchlistItem.self, from: JSONEncoder().encode(item)) == item)
  }

  @Test func checklistItemDecodesLegacyShape() throws {
    let json = #"{"name":"等30分钟再决定","isChecked":true,"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF"}"#
    let item = try JSONDecoder().decode(ChecklistItem.self, from: Data(json.utf8))
    #expect(item.isChecked)
    #expect(item.name == "等30分钟再决定")
  }

  @Test func templateHasSeventeenDeterministicItems() {
    #expect(ChecklistTemplate.defaultPrompts.count == 17)
    #expect(ChecklistTemplate.defaultItems.map(\.id) == ChecklistTemplate.defaultItems.map(\.id))
    #expect(ChecklistTemplate.defaultItems.first?.id == UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    #expect(ChecklistTemplate.defaultItems.allSatisfy { !$0.isChecked })
  }

  @Test func snapshotOrdersFavoritesFirstAndScoresRows() throws {
    let pins = try WatchlistItem(
      symbol: "PINS",
      name: "Pinterest",
      ladder: PriceLadder(buyLow: 12, buyHigh: 16, fair: 23, trim: 33),
      sortIndex: 0,
      createdAt: fridayOpen,
      updatedAt: fridayOpen
    )
    let aapl = WatchlistItem(symbol: "AAPL", name: "Apple", isFavorite: true, sortIndex: 1, createdAt: fridayOpen, updatedAt: fridayOpen)
    let quotes = ["PINS": Quote(symbol: "PINS", price: dec("14.20"), changePercent: -1.5, asOf: fridayOpen)]
    let snapshot = WatchlistSnapshot.make(items: [pins, aapl], quotes: quotes, now: fridayOpen)
    #expect(snapshot.rows.map(\.symbol) == ["AAPL", "PINS"])
    #expect(snapshot.rows[1].status == .buyZone)
    #expect(abs((snapshot.rows[1].temperature ?? 0) - 21.0) < 0.05)
    #expect(snapshot.rows[0].price == nil)
    #expect(snapshot.rows[0].status == nil)
    #expect(snapshot.quotesAsOf == fridayOpen)
    #expect(try JSONDecoder().decode(WatchlistSnapshot.self, from: JSONEncoder().encode(snapshot)) == snapshot)
  }

  @Test func snapshotOrderIsDeterministicWhenSortKeysTie() throws {
    let zeta = WatchlistItem(symbol: "ZETA", name: "Zeta", sortIndex: 0, createdAt: fridayOpen, updatedAt: fridayOpen)
    let alpha = WatchlistItem(symbol: "ALPHA", name: "Alpha", sortIndex: 0, createdAt: fridayOpen, updatedAt: fridayOpen)
    let forward = WatchlistSnapshot.make(items: [zeta, alpha], quotes: [:], now: fridayOpen)
    let backward = WatchlistSnapshot.make(items: [alpha, zeta], quotes: [:], now: fridayOpen)
    #expect(forward.rows.map(\.symbol) == ["ALPHA", "ZETA"])
    #expect(backward.rows.map(\.symbol) == ["ALPHA", "ZETA"])
  }
}
