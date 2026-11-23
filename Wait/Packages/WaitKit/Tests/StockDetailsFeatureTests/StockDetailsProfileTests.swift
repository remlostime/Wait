//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Domain
import Foundation
import MarketDataClient
import StockDetailsFeature
import Testing

// MARK: - StockDetailsProfileTests

@MainActor
@Suite
struct StockDetailsProfileTests {
  private let profile = CompanyProfile(symbol: "AAPL", name: "Apple Inc", marketCap: 2_650_000_500_000, peRatio: 28.4, asOf: detailsNow)
  private let quote = Quote(symbol: "AAPL", price: 140, asOf: detailsNow)

  private func makeStore(profile: @escaping @Sendable (String) async throws -> CompanyProfile) -> TestStoreOf<StockDetailsFeature> {
    let quote = quote
    return TestStore(initialState: StockDetailsFeature.State(item: Shared(value: detailsItem()))) {
      StockDetailsFeature()
    } withDependencies: {
      $0.date.now = detailsNow
      $0.marketData.quotes = { _, policy in
        if policy == .cacheOnly { throw MarketDataError.notCached }
        return [quote]
      }
      $0.marketData.profile = profile
    }
  }

  @Test
  func taskLoadsTheQuoteThenTheProfile() async {
    let profile = profile
    let store = makeStore { _ in profile }
    await store.send(.task)
    await store.receive(\.quoteLoaded) { $0.quote = self.quote }
    await store.receive(\.profileLoaded) { $0.profile = profile }
  }

  @Test
  func aMissingProfileKeepsTheScreenUsable() async {
    let store = makeStore { _ in throw MarketDataError.notFound }
    await store.send(.task)
    await store.receive(\.quoteLoaded) { $0.quote = self.quote }
    await store.receive(\.profileFailed)
    #expect(store.state.profile == nil)
  }
}
