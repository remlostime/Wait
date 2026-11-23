//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import MarketDataClient
import Testing

// MARK: - RecordingHTTP

actor RecordingHTTP {
  // MARK: Lifecycle

  init(_ responder: @escaping @Sendable (URL) -> (Data, Int)) {
    self.responder = responder
  }

  // MARK: Internal

  private(set) var urls: [URL] = []

  func get(_ url: URL) -> (Data, HTTPURLResponse) {
    urls.append(url)
    let (data, status) = responder(url)
    return (data, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
  }

  // MARK: Private

  private let responder: @Sendable (URL) -> (Data, Int)
}

func fixture(_ name: String) -> Data {
  // swiftlint:disable:next force_try
  try! Data(contentsOf: Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!)
}

/// A batch body with a minimal valid quote for each symbol.
func batchJSON(_ symbols: [String]) -> Data {
  let entries = symbols.map { #""\#($0)": {"close": "1.00", "timestamp": 1795208400}"# }
  return Data(("{" + entries.joined(separator: ",") + "}").utf8)
}

func query(_ url: URL) -> [String: String] {
  Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
}

// MARK: - TwelveDataMarketDataTests

@Suite struct TwelveDataMarketDataTests {
  func client(_ http: RecordingHTTP) -> MarketDataClient {
    .twelveData(apiKey: "test-key", get: { url in await http.get(url) })
  }

  @Test func batchQuotesSkipErroredAndGarbageSymbols() async throws {
    let http = RecordingHTTP { _ in (fixture("twelvedata-quote-batch"), 200) }
    let quotes = try await client(http).quotes(["AAPL", "XXXX", "BAD"], .useCache)
    #expect(quotes.map(\.symbol) == ["AAPL"])
    let aapl = try #require(quotes.first)
    #expect(aapl.price == dec("189.98"))
    #expect(aapl.previousClose == dec("187.66"))
    #expect(abs((aapl.changePercent ?? 0) - 1.23628) < 0.00001)
    #expect(aapl.volume == 51_234_567)
    #expect(aapl.fiftyTwoWeekHigh == dec("199.62"))
    #expect(aapl.asOf == Date(timeIntervalSince1970: 1_795_208_400))
  }

  @Test func singleSymbolUsesTheSingleObjectShape() async throws {
    let http = RecordingHTTP { _ in (fixture("twelvedata-quote-single"), 200) }
    let quotes = try await client(http).quotes(["MSFT"], .useCache)
    #expect(quotes.map(\.price) == [dec("414.25")])
  }

  @Test func quotesAreChunkedByEight() async throws {
    let http = RecordingHTTP { _ in (Data("{}".utf8), 200) }
    let symbols = (1 ... 10).map { "S\($0)" }
    _ = try await client(http).quotes(symbols, .useCache)
    let urls = await http.urls
    #expect(urls.count == 2)
    #expect(query(urls[0])["symbol"]?.split(separator: ",").count == 8)
    #expect(query(urls[1])["symbol"] == "S9,S10")
  }

  @Test func midListRateLimitThrowsThePartialQuotes() async throws {
    let http = RecordingHTTP { url in
      let symbols = (query(url)["symbol"] ?? "").split(separator: ",").map(String.init)
      return symbols.count == 8 ? (batchJSON(symbols), 200) : (fixture("twelvedata-rate-limited"), 200)
    }
    let symbols = (1 ... 10).map { "S\($0)" }
    let error = await #expect(throws: PartialQuotesError.self) {
      try await client(http).quotes(symbols, .useCache)
    }
    #expect(error?.quotes.map(\.symbol) == Array(symbols.prefix(8)))
    #expect(error?.retryAfter == .seconds(60))
  }

  @Test func rateLimitedBodyWithHTTP200Throws() async {
    let http = RecordingHTTP { _ in (fixture("twelvedata-rate-limited"), 200) }
    await #expect(throws: MarketDataError.rateLimited(retryAfter: .seconds(60))) {
      try await client(http).quotes(["AAPL"], .useCache)
    }
  }

  @Test func requestsCarryTheKeyAndUTC() async throws {
    let http = RecordingHTTP { _ in (fixture("twelvedata-time-series-1day"), 200) }
    _ = try await client(http).series("AAPL", .oneYear, .useCache)
    let url = try #require(await http.urls.first)
    #expect(url.path == "/time_series")
    #expect(query(url) == ["apikey": "test-key", "interval": "1day", "outputsize": "252", "symbol": "AAPL", "timezone": "UTC"])
  }

  @Test func dailySeriesParsesMonthsCorrectlyAndSortsOldestFirst() async throws {
    let http = RecordingHTTP { _ in (fixture("twelvedata-time-series-1day"), 200) }
    let series = try await client(http).series("AAPL", .oneYear, .useCache)
    #expect(series.points.map(\.date) == [Date(timeIntervalSince1970: 1_795_089_600), Date(timeIntervalSince1970: 1_795_176_000)])
    #expect(series.points.map(\.close) == [dec("187.66"), dec("189.98")])
  }

  @Test func oneDayKeepsOnlyTheLastSession() async throws {
    let http = RecordingHTTP { _ in (fixture("twelvedata-time-series-5min"), 200) }
    let series = try await client(http).series("AAPL", .oneDay, .useCache)
    #expect(series.points.map(\.date) == [Date(timeIntervalSince1970: 1_795_207_800), Date(timeIntervalSince1970: 1_795_208_100)])
    #expect(query(try #require(await http.urls.first))["interval"] == "5min")
  }

  @Test func searchKeepsUSListedEquityTypes() async throws {
    let http = RecordingHTTP { _ in (fixture("twelvedata-search"), 200) }
    let results = try await client(http).search("app")
    #expect(results.map(\.symbol) == ["AAPL", "APLE", "AAPU"]) // Mexico listing dropped; REIT and ETF kept
    #expect(results.first?.name == "Apple Inc")
  }

  @Test func profileIsUnavailable() async {
    let http = RecordingHTTP { _ in (Data(), 200) }
    await #expect(throws: MarketDataError.unavailable) {
      try await client(http).profile("AAPL")
    }
  }
}
