//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Dependencies
import Domain
import Foundation
import MarketDataClient
import Testing

@Suite struct MarketDataErrorTests {
  @Test func mapsArbitraryErrors() throws {
    #expect(try MarketDataError(MarketDataError.notFound) == .notFound)
    if case .network = try MarketDataError(URLError(.notConnectedToInternet)) {} else {
      Issue.record("URLError should map to .network")
    }
    let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad"))
    if case .decoding = try MarketDataError(decoding) {} else {
      Issue.record("DecodingError should map to .decoding")
    }
    #expect(try MarketDataError(PartialQuotesError(quotes: [], retryAfter: .seconds(30))) == .rateLimited(retryAfter: .seconds(30)))
  }

  @Test func cancellationIsRethrownNotWrapped() {
    #expect(throws: CancellationError.self) { try MarketDataError(CancellationError()) }
    #expect(throws: CancellationError.self) { try MarketDataError(URLError(.cancelled)) }
  }

  @Test func userMessages() {
    #expect(MarketDataError.rateLimited(retryAfter: .seconds(60)).userMessage == "Quotes delayed — rate limited")
    #expect(MarketDataError.notCached.userMessage == "No cached data yet")
  }

  @Test func dependencyCanBeOverridden() async throws {
    let quotes = try await withDependencies {
      $0.marketData.quotes = { symbols, _ in symbols.map { Quote(symbol: $0, price: 1, asOf: fridayOpen) } }
    } operation: {
      @Dependency(\.marketData) var marketData
      return try await marketData.quotes(["AAPL"], .useCache)
    }
    #expect(quotes.map(\.symbol) == ["AAPL"])
  }
}
