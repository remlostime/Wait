//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

// swiftlint:disable force_try

import AppFeature
import ComposableArchitecture
import Connectivity
import DependenciesTestSupport
import Domain
import Foundation
import MarketDataClient
import Persistence
import StockDetailsFeature
import Testing
import WatchlistFeature

let appNow = Date(timeIntervalSince1970: 1_795_186_800)

@MainActor
@Suite(.dependencies { $0.defaultFileStorage = .inMemory })
struct AppFeatureTests {
  func seedAAPL() {
    @Shared(.watchlist) var watchlist
    $watchlist.withLock {
      $0 = [WatchlistItem(symbol: "AAPL", name: "Apple", ladder: try! PriceLadder(buyHigh: 100), createdAt: appNow, updatedAt: appNow)]
    }
  }

  @Test func deepLinkParsing() {
    #expect(DeepLink(url: URL(string: "wait://stock/aapl")!) == .stock("AAPL"))
    #expect(DeepLink(url: URL(string: "wait://stock/BRK.B")!) == .stock("BRK.B"))
    #expect(DeepLink(url: URL(string: "wait://stock/0700.HK")!) == .stock("0700.HK"))
    #expect(DeepLink(url: URL(string: "wait://other/AAPL")!) == nil)
    #expect(DeepLink(url: URL(string: "https://stock/AAPL")!) == nil)
    #expect(DeepLink(url: URL(string: "wait://stock/")!) == nil)
    #expect(DeepLink(url: URL(string: "WAIT://Stock/aapl")!) == .stock("AAPL"))
    #expect(DeepLink(url: URL(string: "Wait://STOCK/BRK.B")!) == .stock("BRK.B"))
    #expect(DeepLink(url: URL(string: "HTTPS://stock/AAPL")!) == nil)
    #expect(DeepLink.stock("AAPL").url.absoluteString == "wait://stock/AAPL")
  }

  @Test func didFinishLaunchingPublishesASnapshot() async {
    seedAAPL()
    let clock = TestClock()
    let published = LockIsolated<[WatchlistSnapshot]>([])
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.date.now = appNow
      $0.connectivity = .noop
      $0.snapshotClient.publish = { snapshot in published.withValue { $0.append(snapshot) } }
    }
    await store.send(.appDelegate(.didFinishLaunching))
    await clock.advance(by: .seconds(1))
    #expect(published.value.map { $0.rows.map(\.symbol) } == [["AAPL"]])
  }

  @Test func openURLSelectsTheWatchlistAndPushesDetails() async {
    seedAAPL()
    var state = AppFeature.State()
    state.selectedTab = .settings
    let store = TestStore(initialState: state) { AppFeature() }
    await store.send(.openURL(URL(string: "wait://stock/AAPL")!)) {
      $0.selectedTab = .watchlist
      $0.watchlist.path.append(.details(StockDetailsFeature.State(item: Shared($0.watchlist.$items[id: "AAPL"])!)))
    }
  }

  @Test func unknownDeepLinkSymbolOnlySwitchesTabs() async {
    seedAAPL()
    var state = AppFeature.State()
    state.selectedTab = .settings
    let store = TestStore(initialState: state) { AppFeature() }
    await store.send(.openURL(URL(string: "wait://stock/NOPE")!)) {
      $0.selectedTab = .watchlist
    }
  }

  @Test func unknownDeepLinkSymbolKeepsTheNavigationStack() async {
    seedAAPL()
    var state = AppFeature.State()
    state.watchlist.showDetails(symbol: "AAPL")
    let store = TestStore(initialState: state) { AppFeature() }
    await store.send(.openURL(URL(string: "wait://stock/NOPE")!))
    #expect(store.state.watchlist.path.count == 1)
  }

  @Test func backgroundPublishesImmediatelyAndCancelsTheDebouncedPublish() async {
    seedAAPL()
    let clock = TestClock()
    let published = LockIsolated<[WatchlistSnapshot]>([])
    let quote = Quote(symbol: "AAPL", price: 90, asOf: appNow)
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.date.now = appNow
      $0.connectivity = .noop
      $0.snapshotClient.publish = { snapshot in published.withValue { $0.append(snapshot) } }
    }
    // The edit starts a 1 s debounced publish; `.background` must not wait for it.
    await store.send(.watchlist(.quotesLoaded([quote]))) { $0.watchlist.quotes = ["AAPL": quote] }
    await store.send(.scenePhaseChanged(.background))
    await store.finish()
    #expect(published.value.count == 1)
    #expect(published.value.first?.rows.first?.price == 90)
    // The cancelled debounce must not publish a second time.
    await clock.advance(by: .seconds(2))
    #expect(published.value.count == 1)
  }

  @Test func becomingActiveRefreshesQuotesAndPublishesOneSnapshot() async {
    seedAAPL()
    let clock = TestClock()
    let published = LockIsolated<[WatchlistSnapshot]>([])
    let quote = Quote(symbol: "AAPL", price: 90, asOf: appNow)
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.date.now = appNow
      $0.marketData.quotes = { _, _ in [quote] }
      $0.connectivity = .noop
      $0.snapshotClient.publish = { snapshot in published.withValue { $0.append(snapshot) } }
    }
    await store.send(.scenePhaseChanged(.active))
    await store.receive(\.watchlist.sceneBecameActive)
    await store.receive(\.watchlist.quotesLoaded) {
      $0.watchlist.quotes = ["AAPL": quote]
    }
    await clock.advance(by: .seconds(1))
    #expect(published.value.count == 1)
    #expect(published.value.first?.rows.first?.status == .buyZone)
  }

  @Test func burstsOfChangesPublishOnce() async {
    seedAAPL()
    let clock = TestClock()
    let published = LockIsolated<[WatchlistSnapshot]>([])
    let first = Quote(symbol: "AAPL", price: 90, asOf: appNow)
    let second = Quote(symbol: "AAPL", price: 120, asOf: appNow)
    let store = TestStore(initialState: AppFeature.State()) {
      AppFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.date.now = appNow
      $0.connectivity = .noop
      $0.snapshotClient.publish = { snapshot in published.withValue { $0.append(snapshot) } }
    }
    await store.send(.watchlist(.quotesLoaded([first]))) { $0.watchlist.quotes = ["AAPL": first] }
    await clock.advance(by: .milliseconds(500))
    await store.send(.watchlist(.quotesLoaded([second]))) { $0.watchlist.quotes = ["AAPL": second] }
    await clock.advance(by: .seconds(1))
    #expect(published.value.count == 1)
    #expect(published.value.first?.rows.first?.price == 120)
  }
}
