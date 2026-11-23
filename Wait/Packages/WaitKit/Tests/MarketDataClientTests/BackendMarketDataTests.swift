//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import Dependencies
import Domain
import Foundation
@testable import MarketDataClient
import Testing

// MARK: - BackendMarketDataTests

@Suite
struct BackendMarketDataTests {
  private func decode<T: Decodable>(_ json: String) throws -> T {
    try WireDates.makeDecoder().decode(T.self, from: Data(json.utf8))
  }

  @Test
  func mapsQuotesAndDropsUnparseablePrices() async throws {
    let response: QuotesResponseDTO = try decode(#"""
    {"quotes":[
      {"symbol":"AAPL","price":"172.1","previousClose":"170","open":"171","high":"173","low":"170.5","change":"2.1","changePercent":1.2353,
       "volume":null,"fiftyTwoWeekHigh":null,"fiftyTwoWeekLow":null,"asOf":"2026-11-20T15:00:00.000Z","source":"finnhub","stale":true},
      {"symbol":"BAD","price":"n/a","previousClose":null,"open":null,"high":null,"low":null,"change":null,"changePercent":null,
       "volume":null,"fiftyTwoWeekHigh":null,"fiftyTwoWeekLow":null,"asOf":"2026-11-20T15:00:00.000Z","source":"finnhub","stale":false}
    ],"missing":["ZZZZ"]}
    """#)
    var api = APIClient()
    api.quotes = { _ in response }
    let quotes = try await MarketDataClient.backend(api).quotes(["AAPL", "BAD", "ZZZZ"], .useCache)
    #expect(quotes.map(\.symbol) == ["AAPL"])
    let quote = try #require(quotes.first)
    #expect(quote.price == DecimalCoding.parse("172.1"))
    #expect(quote.previousClose == 170)
    #expect(quote.changePercent == 1.2353)
    #expect(quote.isStale)
    #expect(quote.asOf == WireDates.date(from: "2026-11-20T15:00:00.000Z"))
  }

  @Test
  func mapsSeriesSearchAndProfile() async throws {
    let history: HistoryResponseDTO = try decode(#"""
    {"symbol":"AAPL","range":"1D","points":[{"t":"2026-11-20T14:30:00.000Z","c":"171.2"}],"source":"alpaca",
     "asOf":"2026-11-20T15:00:00.000Z","stale":false,"delayedMinutes":15}
    """#)
    let search: SearchResponseDTO = try decode(#"""
    {"results":[{"symbol":"AAPL","name":"APPLE INC","exchange":null,"type":"Common Stock"}]}
    """#)
    let profile: ProfileDTO = try decode(#"""
    {"symbol":"AAPL","name":"Apple Inc","exchange":"NASDAQ","industry":"Technology","logoUrl":"https://example.com/aapl.png",
     "marketCap":"2650000500000","peRatio":28.4,"pbRatio":45.2,"dividendYield":0.55,"roe":147.25,"roa":27.5,"profitMargin":25.31,
     "fiftyTwoWeekHigh":"199.62","fiftyTwoWeekLow":"164.08","beta":1.29,"asOf":"2026-11-20T15:00:00.000Z"}
    """#)
    var api = APIClient()
    api.history = { _, _ in history }
    api.search = { _ in search }
    api.profile = { _ in profile }
    let client = MarketDataClient.backend(api)

    let series = try await client.series("AAPL", .oneDay, .useCache)
    #expect(series.range == .oneDay && series.delayedMinutes == 15 && series.points.map(\.close) == [DecimalCoding.parse("171.2")!])

    #expect(try await client.search("app") == [SymbolSearchResult(symbol: "AAPL", name: "APPLE INC", exchange: nil, type: "Common Stock")])

    let company = try await client.profile("AAPL")
    #expect(company.marketCap == DecimalCoding.parse("2650000500000"))
    #expect(company.logoURL == URL(string: "https://example.com/aapl.png"))
    #expect(company.fiftyTwoWeekLow == DecimalCoding.parse("164.08") && company.peRatio == 28.4)
  }

  private static func quotesJSON(_ symbols: [String]) -> String {
    let items = symbols.map {
      """
      {"symbol":"\($0)","price":"1","previousClose":null,"open":null,"high":null,"low":null,"change":null,"changePercent":null,"volume":null,
       "fiftyTwoWeekHigh":null,"fiftyTwoWeekLow":null,"asOf":"2026-11-20T15:00:00.000Z","source":"finnhub","stale":false}
      """
    }
    return #"{"quotes":[\#(items.joined(separator: ","))],"missing":[]}"#
  }

  /// `SAA`, `SAB`, ... : distinct tickers that pass the server's symbol rule.
  private static func tickers(_ count: Int) -> [String] {
    let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    return (0 ..< count).map { index in "S\(letters[index / 26])\(letters[index % 26])" }
  }

  private static func recordingQuotesAPI(_ calls: LockIsolated<[[String]]>) -> APIClient {
    var api = APIClient()
    api.quotes = { symbols in
      calls.withValue { $0.append(symbols) }
      return try WireDates.makeDecoder().decode(QuotesResponseDTO.self, from: Data(quotesJSON(symbols).utf8))
    }
    return api
  }

  @Test
  func quotesNormalizesAndNeverSendsSymbolsTheServerWouldReject() async throws {
    let calls = LockIsolated<[[String]]>([])
    let quotes = try await MarketDataClient.backend(Self.recordingQuotesAPI(calls)).quotes(["aapl", "0700.HK", "AAPL"], .useCache)
    #expect(calls.value == [["AAPL"]])
    #expect(quotes.map(\.symbol) == ["AAPL"])
  }

  @Test
  func quotesChunksBy50AndMergesTheResults() async throws {
    let calls = LockIsolated<[[String]]>([])
    let symbols = Self.tickers(51)
    let quotes = try await MarketDataClient.backend(Self.recordingQuotesAPI(calls)).quotes(symbols, .useCache)
    #expect(calls.value.map(\.count) == [50, 1])
    #expect(quotes.map(\.symbol) == symbols)
  }

  @Test
  func aRateLimitedLaterChunkReturnsTheEarlierQuotesAsPartial() async throws {
    let symbols = Self.tickers(51)
    var api = APIClient()
    api.quotes = { chunk in
      if chunk.count == 1 { throw APIError(status: 503, code: "UPSTREAM_RATE_LIMITED", message: "", retryAfter: .seconds(30)) }
      return try WireDates.makeDecoder().decode(QuotesResponseDTO.self, from: Data(Self.quotesJSON(chunk).utf8))
    }
    let client = MarketDataClient.backend(api)
    let error = await #expect(throws: PartialQuotesError.self) { try await client.quotes(symbols, .useCache) }
    #expect(error?.quotes.count == 50)
    #expect(error?.retryAfter == .seconds(30))
  }

  @Test
  func emptyOrInvalidInputMakesNoRequest() async throws {
    let client = MarketDataClient.backend(APIClient()) // every endpoint unimplemented: any call fails the test
    #expect(try await client.quotes([], .useCache).isEmpty)
    #expect(try await client.quotes(["0700.HK"], .useCache).isEmpty)
    #expect(try await client.search("   ").isEmpty)
  }

  @Test
  func searchTrimsAndTruncatesTo30Characters() async throws {
    let sent = LockIsolated<String?>(nil)
    var api = APIClient()
    api.search = { query in
      sent.setValue(query)
      return try WireDates.makeDecoder().decode(SearchResponseDTO.self, from: Data(#"{"results":[]}"#.utf8))
    }
    _ = try await MarketDataClient.backend(api).search("  " + String(repeating: "a", count: 40) + " ")
    #expect(sent.value == String(repeating: "a", count: 30))
  }

  @Test
  func mapsAPIErrorsToMarketDataErrors() async {
    var api = APIClient()
    api.quotes = { _ in throw APIError(status: 503, code: "UPSTREAM_RATE_LIMITED", message: "", retryAfter: .seconds(30)) }
    api.profile = { _ in throw APIError(status: 404, code: "NOT_FOUND", message: "") }
    api.search = { _ in throw APIError.transport("offline") }
    api.history = { _, _ in throw APIError(status: 502, code: "UPSTREAM_UNAVAILABLE", message: "") }
    let client = MarketDataClient.backend(api)
    await #expect(throws: MarketDataError.rateLimited(retryAfter: .seconds(30))) { try await client.quotes(["AAPL"], .useCache) }
    await #expect(throws: MarketDataError.notFound) { try await client.profile("ZZZZ") }
    await #expect(throws: MarketDataError.network("offline")) { try await client.search("app") }
    await #expect(throws: MarketDataError.unavailable) { try await client.series("AAPL", .oneYear, .useCache) }
  }
}
