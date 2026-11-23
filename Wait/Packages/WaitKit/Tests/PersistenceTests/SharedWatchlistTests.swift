//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import DependenciesTestSupport
import Domain
import Foundation
import IdentifiedCollections
import Persistence
import Sharing
import Testing

@Suite struct SharedWatchlistTests {
  let t0 = Date(timeIntervalSince1970: 1_795_186_800)
  let later = Date(timeIntervalSince1970: 1_795_186_860.123_9)

  func item(_ symbol: String, _ sortIndex: Int, favorite: Bool = false) -> WatchlistItem {
    WatchlistItem(symbol: symbol, name: symbol, isFavorite: favorite, sortIndex: sortIndex, createdAt: t0, updatedAt: t0)
  }

  @Test func updateStampsMillisecondTruncatedNow() {
    let items = Shared(value: IdentifiedArray(uniqueElements: [item("AAPL", 0)]))
    items.update("AAPL", now: later) { $0.memo = "note" }
    #expect(items.wrappedValue[id: "AAPL"]?.memo == "note")
    #expect(items.wrappedValue[id: "AAPL"]?.updatedAt.millisecondsSince1970 == 1_795_186_860_123)
    #expect(items.wrappedValue[id: "AAPL"]?.updatedAt == later.truncatedToMilliseconds)
  }

  @Test func updateOfUnknownSymbolIsANoop() {
    let items = Shared(value: IdentifiedArray(uniqueElements: [item("AAPL", 0)]))
    items.update("MSFT", now: later) { $0.memo = "x" }
    #expect(items.wrappedValue.map(\.updatedAt) == [t0])
  }

  @Test func addAppendsWithNextSortIndexAndRejectsDuplicates() {
    let items = Shared(value: IdentifiedArray(uniqueElements: [item("AAPL", 4)]))
    #expect(items.add(item("MSFT", 0), now: later))
    #expect(items.wrappedValue[id: "MSFT"]?.sortIndex == 5)
    #expect(items.wrappedValue[id: "MSFT"]?.updatedAt == later.truncatedToMilliseconds)
    #expect(!items.add(item("AAPL", 0), now: later))
    #expect(items.wrappedValue.count == 2)
  }

  @Test func removeDeletes() {
    let items = Shared(value: IdentifiedArray(uniqueElements: [item("AAPL", 0), item("MSFT", 1)]))
    items.remove("AAPL", now: later)
    #expect(items.wrappedValue.ids == ["MSFT"])
  }

  @Test func reorderReusesTheSectionSlotsAndTouchesOnlyMovedItems() {
    let items = Shared(value: IdentifiedArray(uniqueElements: [
      item("A", 0), item("B", 1), item("C", 2), item("F", 3, favorite: true), item("D", 4),
    ]))
    // Others in order A, B, C, D. Move B (offset 1) to before D (offset 3), giving A, C, B, D.
    items.reorder(section: .others, from: IndexSet(integer: 1), to: 3, now: later)
    let value = items.wrappedValue
    #expect(value[id: "A"]?.sortIndex == 0)
    #expect(value[id: "C"]?.sortIndex == 1)
    #expect(value[id: "B"]?.sortIndex == 2)
    #expect(value[id: "D"]?.sortIndex == 4)
    #expect(value[id: "F"]?.sortIndex == 3)
    #expect(value[id: "A"]?.updatedAt == t0)
    #expect(value[id: "D"]?.updatedAt == t0)
    #expect(value[id: "F"]?.updatedAt == t0)
    #expect(value[id: "B"]?.updatedAt == later.truncatedToMilliseconds)
    #expect(value[id: "C"]?.updatedAt == later.truncatedToMilliseconds)
  }

  @Test func sharedItemUpdate() {
    let one = Shared(value: item("AAPL", 0))
    one.update(now: later) { $0.isFavorite = true }
    #expect(one.wrappedValue.isFavorite)
    #expect(one.wrappedValue.updatedAt == later.truncatedToMilliseconds)
  }

  @Test(.dependencies { $0.defaultFileStorage = .inMemory })
  func keysHaveDefaults() {
    @Shared(.watchlist) var watchlist
    @SharedReader(.checklistTemplate) var template
    #expect(watchlist.isEmpty)
    #expect(Array(template) == ChecklistTemplate.defaultItems)
  }
}
