//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

// swiftlint:disable force_try

import ChecklistFeature
import ComposableArchitecture
import DependenciesTestSupport
import Domain
import Foundation
import MarketDataClient
import Persistence
import StockDetailsFeature
import Testing
import WatchlistFeature

let listNow = Date(timeIntervalSince1970: 1_795_186_800)

func listItem(_ symbol: String, _ sortIndex: Int, favorite: Bool = false) -> WatchlistItem {
  WatchlistItem(symbol: symbol, name: symbol, ladder: try! PriceLadder(buyHigh: 100), isFavorite: favorite, sortIndex: sortIndex, createdAt: .distantPast, updatedAt: .distantPast)
}

@MainActor
@Suite(.dependencies { $0.defaultFileStorage = .inMemory })
struct WatchlistFeatureTests {
  func seed(_ items: [WatchlistItem]) {
    @Shared(.watchlist) var watchlist
    $watchlist.withLock { $0 = IdentifiedArray(uniqueElements: items) }
  }

  @Test func loadsCachedThenFreshQuotes() async {
    seed([listItem("AAPL", 0)])
    let stale = Quote(symbol: "AAPL", price: 100, asOf: listNow, isStale: true)
    let fresh = Quote(symbol: "AAPL", price: 101, asOf: listNow)
    let store = TestStore(initialState: WatchlistFeature.State()) {
      WatchlistFeature()
    } withDependencies: {
      $0.marketData.quotes = { _, policy in policy == .cacheOnly ? [stale] : [fresh] }
    }
    await store.send(.task)
    await store.receive(\.quotesLoaded) {
      $0.quotes = ["AAPL": stale]
      $0.quotesStatus = .delayed("Showing cached prices")
    }
    await store.receive(\.quotesLoaded) {
      $0.quotes = ["AAPL": fresh]
      $0.quotesStatus = .idle
    }
  }

  @Test func rateLimitKeepsExistingQuotes() async {
    seed([listItem("AAPL", 0)])
    var state = WatchlistFeature.State()
    state.quotes = ["AAPL": Quote(symbol: "AAPL", price: 99, asOf: listNow)]
    let store = TestStore(initialState: state) {
      WatchlistFeature()
    } withDependencies: {
      $0.marketData.quotes = { _, policy in
        throw policy == .cacheOnly ? MarketDataError.notCached : MarketDataError.rateLimited(retryAfter: .seconds(60))
      }
    }
    await store.send(.task)
    await store.receive(\.quotesFailed) {
      $0.quotesStatus = .delayed("Quotes delayed — rate limited")
    }
  }

  @Test func swipeDeleteRemovesTheItem() async {
    seed([listItem("AAPL", 0), listItem("MSFT", 1)])
    let store = TestStore(initialState: WatchlistFeature.State()) {
      WatchlistFeature()
    } withDependencies: {
      $0.date.now = listNow
    }
    await store.send(.deleteSwiped(symbol: "AAPL")) {
      $0.$items.withLock { _ = $0.remove(id: "AAPL") }
    }
  }

  @Test func favoriteSwipeTogglesAndStamps() async {
    seed([listItem("AAPL", 0)])
    let store = TestStore(initialState: WatchlistFeature.State()) {
      WatchlistFeature()
    } withDependencies: {
      $0.date.now = listNow
    }
    await store.send(.favoriteSwiped(symbol: "AAPL")) {
      $0.$items.withLock {
        $0[id: "AAPL"]?.isFavorite = true
        $0[id: "AAPL"]?.updatedAt = listNow
      }
    }
    #expect(store.state.favorites.map(\.symbol) == ["AAPL"])
    #expect(store.state.others.isEmpty)
  }

  @Test func reorderOnlyTouchesTheSection() async {
    seed([listItem("A", 0), listItem("B", 1), listItem("F", 2, favorite: true)])
    let store = TestStore(initialState: WatchlistFeature.State()) {
      WatchlistFeature()
    } withDependencies: {
      $0.date.now = listNow
    }
    await store.send(.moved(.others, from: IndexSet(integer: 1), to: 0)) {
      $0.$items.withLock {
        $0[id: "B"]?.sortIndex = 0
        $0[id: "B"]?.updatedAt = listNow
        $0[id: "A"]?.sortIndex = 1
        $0[id: "A"]?.updatedAt = listNow
      }
    }
  }

  @Test func rowTapPushesDetailsAndDetailsDelegatesNavigate() async {
    seed([listItem("AAPL", 0)])
    let store = TestStore(initialState: WatchlistFeature.State()) {
      WatchlistFeature()
    } withDependencies: {
      $0.date.now = listNow
    }
    await store.send(.rowTapped(symbol: "AAPL")) {
      $0.path.append(.details(StockDetailsFeature.State(item: Shared($0.$items[id: "AAPL"])!)))
    }
    await store.send(.path(.element(id: 0, action: .details(.delegate(.openChecklist(symbol: "AAPL")))))) {
      $0.path.append(.checklist(ChecklistFeature.State(item: Shared($0.$items[id: "AAPL"])!)))
    }
    await store.send(.path(.element(id: 0, action: .details(.delegate(.deleteConfirmed(symbol: "AAPL")))))) {
      $0.path.pop(from: 0)
      $0.$items.withLock { _ = $0.remove(id: "AAPL") }
    }
  }

  @Test func unknownSymbolDoesNotPush() {
    var state = WatchlistFeature.State()
    #expect(state.showDetails(symbol: "NOPE") == false)
    #expect(state.path.isEmpty)
  }

  @Test func addedStockIsAppendedAndTheSheetDismissed() async {
    seed([listItem("AAPL", 0)])
    var state = WatchlistFeature.State()
    state.destination = .addStock(AddStockFeature.State())
    let added = WatchlistItem(symbol: "MSFT", name: "Microsoft", createdAt: listNow, updatedAt: listNow)
    let quote = Quote(symbol: "MSFT", price: 300, asOf: listNow)
    let store = TestStore(initialState: state) {
      WatchlistFeature()
    } withDependencies: {
      $0.date.now = listNow
      $0.marketData.quotes = { _, _ in [quote] }
    }
    await store.send(.destination(.presented(.addStock(.delegate(.added(added)))))) {
      var expected = added
      expected.sortIndex = 1
      $0.$items.withLock { $0.append(expected) }
      $0.destination = nil
    }
    await store.receive(\.symbolQuotesLoaded) {
      $0.quotes = ["MSFT": quote]
    }
  }

  @Test func singleSymbolLoadKeepsTheRateLimitBanner() async {
    seed([listItem("AAPL", 0)])
    var state = WatchlistFeature.State()
    state.destination = .addStock(AddStockFeature.State())
    state.quotesStatus = .delayed("Quotes delayed — rate limited")
    let added = WatchlistItem(symbol: "MSFT", name: "Microsoft", createdAt: listNow, updatedAt: listNow)
    let quote = Quote(symbol: "MSFT", price: 300, asOf: listNow)
    let store = TestStore(initialState: state) {
      WatchlistFeature()
    } withDependencies: {
      $0.date.now = listNow
      $0.marketData.quotes = { _, _ in [quote] }
    }
    await store.send(.destination(.presented(.addStock(.delegate(.added(added)))))) {
      var expected = added
      expected.sortIndex = 1
      $0.$items.withLock { $0.append(expected) }
      $0.destination = nil
    }
    // `quotesStatus` stays `.delayed`: the closure changes only `quotes`.
    await store.receive(\.symbolQuotesLoaded) {
      $0.quotes = ["MSFT": quote]
    }
  }

  @Test func pullToRefreshRequestsSyncAndReloads() async {
    seed([listItem("AAPL", 0)])
    let fresh = Quote(symbol: "AAPL", price: 101, asOf: listNow)
    let store = TestStore(initialState: WatchlistFeature.State()) {
      WatchlistFeature()
    } withDependencies: {
      $0.marketData.quotes = { _, policy in
        #expect(policy == .reload)
        return [fresh]
      }
    }
    await store.send(.refreshPulled) { $0.quotesStatus = .refreshing }
    await store.receive(\.delegate.refreshRequested)
    await store.receive(\.quotesLoaded) {
      $0.quotes = ["AAPL": fresh]
      $0.quotesStatus = .idle
    }
  }
}
