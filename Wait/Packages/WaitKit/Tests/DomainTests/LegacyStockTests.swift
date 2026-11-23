//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Testing

// MARK: - LegacyStockTests

@Suite struct LegacyStockTests {
  func fixture() throws -> [LegacyStock] {
    let url = try #require(Bundle.module.url(forResource: "legacy-stocks", withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode([LegacyStock].self, from: Data(contentsOf: url))
  }

  @Test func decodesTheLegacyMoneyShapes() throws {
    let stocks = try fixture()
    #expect(stocks.count == 6)
    #expect(stocks[0].expectedPrice?.amount.rounded(scale: 4) == dec("150.12"))
    #expect(stocks[3].expectedPrice?.amount == dec("80.5"))
    #expect(stocks[0].expectedPriceHistory?.first?.date == Date(timeIntervalSinceReferenceDate: 690_000_000.123_456_7))
    #expect(stocks[5].memo == nil)
  }

  @Test func legacyMoneyAcceptsSingleValues() throws {
    let number = try JSONDecoder().decode(LegacyMoney.self, from: Data("12.5".utf8))
    let string = try JSONDecoder().decode(LegacyMoney.self, from: Data(#""12.5""#.utf8))
    #expect(number.amount == dec("12.5"))
    #expect(string.amount == dec("12.5"))
  }

  @Test func mapsSkipsEmptyAndDedupes() throws {
    let now = fridayOpen
    let aaplChecklist = [ChecklistItem(id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!, name: "Custom", isChecked: true)]
    let items = try LegacyStockMapper.items(
      from: fixture(),
      checklists: ["AAPL": aaplChecklist, "BABA": []],
      template: ChecklistTemplate.defaultItems,
      now: now
    )
    #expect(items.map(\.symbol) == ["AAPL", "BABA", "ZERO"])
    #expect(items.map(\.sortIndex) == [0, 1, 2])

    let aapl = items[0]
    #expect(aapl.name == "Apple Inc")
    #expect(aapl.memo == "Long term\nhold")
    #expect(try aapl.ladder == PriceLadder(buyHigh: dec("150.12")))
    #expect(aapl.ladderHistory.count == 2)
    #expect(aapl.ladderHistory[0].ladder.buyHigh == 160)
    // D21: the fractional legacy date is truncated to whole milliseconds (2022-11-13T02:40:00.123Z).
    #expect(aapl.createdAt.millisecondsSince1970 == 1_668_307_200_123)
    #expect(aapl.ladderHistory[0].date == aapl.createdAt)
    #expect(aapl.updatedAt == now)
    #expect(!aapl.isFavorite)
    #expect(aapl.checklist == aaplChecklist)

    #expect(items[1].name == "Alibaba") // " baba " and "BABA" map to the same key; the first one wins
    #expect(items[1].ladder.buyHigh == dec("80.5"))
    #expect(items[1].createdAt == now)
    #expect(items[1].checklist.isEmpty) // looked up under the mapped key "BABA"
    #expect(items[2].checklist == ChecklistTemplate.defaultItems)
    #expect(items[2].ladder.isEmpty)
  }

  @Test func dropsNonPositiveHistoryAndCapsAtTwoHundred() throws {
    let json = #"""
    [{"symbol":"R","expectedPrice":{"amount":1.23456,"currencyCode":"USD"},"expectedPriceHistory":[
      {"date":100,"price":{"amount":0,"currencyCode":"USD"}},
      {"date":150,"price":{"amount":-3,"currencyCode":"USD"}},
      {"date":200,"price":{"amount":2,"currencyCode":"USD"}}]}]
    """#
    let stocks = try JSONDecoder().decode([LegacyStock].self, from: Data(json.utf8))
    let item = try #require(LegacyStockMapper.items(from: stocks, checklists: [:], template: [], now: fridayOpen).first)
    #expect(item.ladder.buyHigh == dec("1.2346"))
    #expect(item.ladderHistory.count == 1)
    #expect(item.ladderHistory[0].ladder.buyHigh == 2)

    let entries = (1 ... 205).map { #"{"date":\#($0),"price":{"amount":\#($0),"currencyCode":"USD"}}"# }.joined(separator: ",")
    let longJSON = #"[{"symbol":"CAP","expectedPrice":{"amount":9,"currencyCode":"USD"},"expectedPriceHistory":[\#(entries)]}]"#
    let longStocks = try JSONDecoder().decode([LegacyStock].self, from: Data(longJSON.utf8))
    let capped = try #require(LegacyStockMapper.items(from: longStocks, checklists: [:], template: [], now: fridayOpen).first)
    #expect(capped.ladderHistory.count == LadderRevision.maxCount)
    #expect(capped.ladderHistory.first?.ladder.buyHigh == 6) // the oldest five are dropped
    #expect(capped.ladderHistory.last?.ladder.buyHigh == 205)
  }
}
