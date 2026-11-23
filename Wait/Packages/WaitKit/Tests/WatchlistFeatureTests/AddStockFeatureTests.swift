//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import DependenciesTestSupport
import Domain
import Foundation
import MarketDataClient
import Persistence
import StockDetailsFeature
import Testing
import WatchlistFeature

let addNow = Date(timeIntervalSince1970: 1_795_186_800)
let aapl = SymbolSearchResult(symbol: "AAPL", name: "Apple Inc", exchange: "NASDAQ", type: "Common Stock")
let msft = SymbolSearchResult(symbol: "MSFT", name: "Microsoft", exchange: "NASDAQ", type: "Common Stock")

@MainActor
@Suite(.dependencies { $0.defaultFileStorage = .inMemory })
struct AddStockFeatureTests {
  @Test func debounceSendsExactlyOneSearch() async {
    let clock = TestClock()
    let queries = LockIsolated<[String]>([])
    let store = TestStore(initialState: AddStockFeature.State()) {
      AddStockFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.marketData.search = { query in
        queries.withValue { $0.append(query) }
        return [aapl]
      }
    }
    await store.send(\.binding.query, "ap") {
      $0.query = "ap"
      $0.isSearching = true
    }
    await store.send(\.binding.query, "app") { $0.query = "app" }
    await clock.advance(by: .milliseconds(300))
    await store.receive(\.searchLoaded) {
      $0.isSearching = false
      $0.results = [aapl]
    }
    #expect(queries.value == ["app"])
  }

  @Test func clearingTheQueryClearsResultsWithoutSearching() async {
    var state = AddStockFeature.State()
    state.query = "app"
    state.results = [aapl]
    let store = TestStore(initialState: state) { AddStockFeature() }
    await store.send(\.binding.query, "") {
      $0.query = ""
      $0.results = []
    }
  }

  @Test func alreadyAddedSymbolShowsANotice() async {
    @Shared(.watchlist) var watchlist
    $watchlist.withLock { $0 = [WatchlistItem(symbol: "AAPL", name: "Apple", createdAt: .distantPast, updatedAt: .distantPast)] }
    let store = TestStore(initialState: AddStockFeature.State()) { AddStockFeature() }
    await store.send(.resultTapped(aapl)) {
      $0.errorMessage = "AAPL is already on your watchlist."
    }
  }

  @Test func savingTheLadderEmitsAnItemSeededFromTheTemplate() async throws {
    let store = TestStore(initialState: AddStockFeature.State()) {
      AddStockFeature()
    } withDependencies: {
      $0.date.now = addNow
      $0.uuid = .incrementing
    }
    await store.send(.resultTapped(msft)) {
      $0.pending = msft
      $0.destination = .ladderEditor(LadderEditorFeature.State(symbol: "MSFT", ladder: .empty, currentPrice: nil))
    }
    let ladder = try PriceLadder(buyHigh: 300)
    await store.send(.destination(.presented(.ladderEditor(.delegate(.saved(ladder))))))
    let expected = WatchlistItem(
      symbol: "MSFT",
      name: "Microsoft",
      ladder: ladder,
      checklist: ChecklistTemplate.defaultItems.enumerated().map { ChecklistItem(id: UUID($0.offset), name: $0.element.name) },
      ladderHistory: [LadderRevision(date: addNow, ladder: ladder)],
      createdAt: addNow,
      updatedAt: addNow
    )
    await store.receive(\.delegate.added, expected)
  }

  @Test func searchFailureShowsAMessage() async {
    let clock = TestClock()
    let store = TestStore(initialState: AddStockFeature.State()) {
      AddStockFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.marketData.search = { _ in throw MarketDataError.rateLimited(retryAfter: nil) }
    }
    await store.send(\.binding.query, "x") {
      $0.query = "x"
      $0.isSearching = true
    }
    await clock.advance(by: .milliseconds(300))
    await store.receive(\.searchFailed) {
      $0.isSearching = false
      $0.errorMessage = "Quotes delayed — rate limited"
    }
  }
}
