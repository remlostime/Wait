//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Dependencies
import DependenciesMacros
import Domain
import Foundation
import Logging

// MARK: - MarketDataClient

/// Everything the app needs from market data. Inject it through `@Dependency(\.marketData)`.
@DependencyClient
public struct MarketDataClient: Sendable {
  public var quotes: @Sendable (_ symbols: [String], _ policy: CachePolicy) async throws -> [Quote]
  public var series: @Sendable (_ symbol: String, _ range: ChartRange, _ policy: CachePolicy) async throws -> PriceSeries
  public var search: @Sendable (_ query: String) async throws -> [SymbolSearchResult]
  public var profile: @Sendable (_ symbol: String) async throws -> CompanyProfile
}

// MARK: TestDependencyKey

extension MarketDataClient: TestDependencyKey {
  public static let testValue = MarketDataClient()

  public static let previewValue = MarketDataClient(
    quotes: { symbols, _ in
      symbols.map { Quote(symbol: $0, price: Decimal(string: "123.45")!, previousClose: Decimal(string: "120")!, changePercent: 2.88, asOf: Date()) }
    },
    series: { symbol, range, _ in
      let start = Date().addingTimeInterval(-86400 * 30)
      let points = (0 ..< 30).map { PricePoint(date: start.addingTimeInterval(Double($0) * 86400), close: Decimal(100 + ($0 % 7) * 3)) }
      return PriceSeries(symbol: symbol, range: range, points: points, asOf: Date())
    },
    search: { query in
      [SymbolSearchResult(symbol: query.uppercased(), name: "\(query.uppercased()) Inc", exchange: "NASDAQ", type: "Common Stock")]
    },
    profile: { _ in throw MarketDataError.unavailable }
  )
}

public extension DependencyValues {
  var marketData: MarketDataClient {
    get { self[MarketDataClient.self] }
    set { self[MarketDataClient.self] = newValue }
  }
}

// MARK: DependencyKey

extension MarketDataClient: DependencyKey {
  /// Plan 02: Twelve Data stopgap. The key comes from Info.plist `TwelveDataAPIKey`, which is `$(TWELVE_DATA_API_KEY)` from `Secrets.xcconfig`.
  /// An unset key (empty, an unexpanded `$(...)` or the placeholder) gives a client whose every call throws `.unavailable` with no request.
  /// A `static let` runs once, so the error is logged once.
  public static let liveValue: MarketDataClient = {
    let key = Bundle.main.object(forInfoDictionaryKey: "TwelveDataAPIKey") as? String
    if !TwelveDataAPIKey.isUsable(key) {
      Log.network.error("TwelveDataAPIKey is not configured; set TWELVE_DATA_API_KEY in Secrets.xcconfig. Market data is unavailable.")
    }
    return MarketDataClient.cached(.twelveData(apiKey: key ?? ""), disk: .live, now: { Date() })
  }()
}
