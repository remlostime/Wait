//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Domain
import Foundation
import MarketDataClient
import StockChartFeature
import Testing

let chartDate = Date(timeIntervalSince1970: 1_795_186_800)
let oneYear = PriceSeries(symbol: "AAPL", range: .oneYear, points: points(["10", "12"]), asOf: chartDate)

@MainActor
@Suite struct StockChartFeatureTests {
  @Test func taskFetchesOnlyTheSelectedRange() async {
    let calls = LockIsolated<[String]>([])
    let store = TestStore(initialState: StockChartFeature.State(symbol: "AAPL")) {
      StockChartFeature()
    } withDependencies: {
      $0.marketData.series = { _, range, policy in
        calls.withValue { $0.append("\(range.rawValue):\(policy)") }
        if policy == .cacheOnly { throw MarketDataError.notCached }
        return oneYear
      }
    }
    await store.send(.task) { $0.loading = [.oneYear] }
    await store.receive(\.seriesLoaded) {
      $0.loading = []
      $0.series[.oneYear] = oneYear
    }
    #expect(calls.value == ["1Y:cacheOnly", "1Y:useCache"])
  }

  @Test func cachedSeriesShowsWhileStillLoading() async {
    let stale = oneYear.with(isStale: true)
    let store = TestStore(initialState: StockChartFeature.State(symbol: "AAPL")) {
      StockChartFeature()
    } withDependencies: {
      $0.marketData.series = { _, _, policy in policy == .cacheOnly ? stale : oneYear }
    }
    await store.send(.task) { $0.loading = [.oneYear] }
    await store.receive(\.cachedSeriesLoaded) { $0.series[.oneYear] = stale } // still loading
    await store.receive(\.seriesLoaded) {
      $0.loading = []
      $0.series[.oneYear] = oneYear
    }
  }

  @Test func reselectingALoadedRangeMakesNoCall() async {
    var state = StockChartFeature.State(symbol: "AAPL")
    state.series[.oneYear] = oneYear
    let month = PriceSeries(symbol: "AAPL", range: .oneMonth, points: [], asOf: chartDate)
    let store = TestStore(initialState: state) {
      StockChartFeature()
    } withDependencies: {
      $0.marketData.series = { _, _, policy in
        if policy == .cacheOnly { throw MarketDataError.notCached }
        return month
      }
    }
    await store.send(.rangeSelected(.oneMonth)) {
      $0.range = .oneMonth
      $0.loading = [.oneMonth]
    }
    await store.receive(\.seriesLoaded) {
      $0.loading = []
      $0.series[.oneMonth] = month
    }
    await store.send(.rangeSelected(.oneYear)) { $0.range = .oneYear }
  }

  @Test func failureThenRetryReloads() async {
    let attempts = LockIsolated(0)
    let store = TestStore(initialState: StockChartFeature.State(symbol: "AAPL")) {
      StockChartFeature()
    } withDependencies: {
      $0.marketData.series = { _, _, policy in
        if policy == .cacheOnly { throw MarketDataError.notCached }
        attempts.withValue { $0 += 1 }
        if attempts.value == 1 { throw MarketDataError.network("down") }
        #expect(policy == .reload)
        return oneYear
      }
    }
    await store.send(.task) { $0.loading = [.oneYear] }
    await store.receive(\.seriesFailed) {
      $0.loading = []
      $0.failed[.oneYear] = .network("down")
    }
    await store.send(.retryTapped) {
      $0.loading = [.oneYear]
      $0.failed = [:]
    }
    await store.receive(\.seriesLoaded) {
      $0.loading = []
      $0.series[.oneYear] = oneYear
    }
  }

  @Test func selectionSnapsToAValidIndex() async {
    var state = StockChartFeature.State(symbol: "AAPL")
    state.series[.oneYear] = oneYear
    let store = TestStore(initialState: state) { StockChartFeature() }
    await store.send(.selectionChanged(7)) { $0.selectedIndex = 1 }
    #expect(store.state.selectedPoint?.close == 12)
    await store.send(.selectionChanged(nil)) { $0.selectedIndex = nil }
  }
}
