//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Logging

/// GET a URL and return the body plus the HTTP response. Tests inject a fake.
public typealias HTTPGet = @Sendable (URL) async throws -> (Data, HTTPURLResponse)

public extension URLSession {
  var httpGet: HTTPGet {
    { [self] url in
      let (data, response) = try await data(from: url)
      guard let http = response as? HTTPURLResponse else {
        throw MarketDataError.network("Non-HTTP response")
      }
      return (data, http)
    }
  }
}

public extension MarketDataClient {
  /// The stopgap adapter until plan 04. Always wrap it with `.cached(...)`.
  static func twelveData(
    apiKey: String,
    baseURL: URL = URL(string: "https://api.twelvedata.com")!,
    get: @escaping HTTPGet = URLSession.shared.httpGet,
    now: @escaping @Sendable () -> Date = { Date() }
  ) -> MarketDataClient {
    // An unset key (empty, an unexpanded `$(...)` or the placeholder) would only earn 401s: fail fast with no request.
    guard TwelveDataAPIKey.isUsable(apiKey) else {
      return MarketDataClient(
        quotes: { _, _ in throw MarketDataError.unavailable },
        series: { _, _, _ in throw MarketDataError.unavailable },
        search: { _ in throw MarketDataError.unavailable },
        profile: { _ in throw MarketDataError.unavailable }
      )
    }
    let api = TwelveDataAPI(apiKey: apiKey, baseURL: baseURL, get: get, now: now)
    return MarketDataClient(
      quotes: { symbols, _ in try await api.quotes(symbols) },
      series: { symbol, range, _ in try await api.series(symbol, range: range) },
      search: { query in try await api.search(query) },
      profile: { _ in throw MarketDataError.unavailable }
    )
  }
}

// MARK: - TwelveDataAPI

struct TwelveDataAPI: Sendable {
  // MARK: Internal

  static let batchSize = 8

  let apiKey: String
  let baseURL: URL
  let get: HTTPGet
  let now: @Sendable () -> Date

  static func parameters(for range: ChartRange) -> (interval: String, outputSize: Int) {
    switch range {
      case .oneDay: ("5min", 80)
      case .oneWeek: ("30min", 65)
      case .oneMonth: ("1day", 22)
      case .oneYear: ("1day", 252)
      case .fiveYears: ("1week", 260)
    }
  }

  /// One request per 8 symbols (1 credit per symbol).
  /// - A failure on the first chunk throws the mapped `MarketDataError`.
  /// - A failure on a later chunk (a 429 or anything else) throws `PartialQuotesError` with the quotes so far and the underlying error,
  ///   so the caching decorator keeps those quotes and still cools down on a 429.
  /// - A single-symbol chunk whose body is a top-level `.notFound` error means "no quote for that symbol": it is skipped.
  ///   If nothing at all came back, the lone `.notFound` is thrown so a search for one unknown symbol still reports it.
  func quotes(_ symbols: [String]) async throws -> [Quote] {
    var result: [Quote] = []
    var skippedUnknown = false
    for start in stride(from: 0, to: symbols.count, by: Self.batchSize) {
      let chunk = Array(symbols[start ..< min(start + Self.batchSize, symbols.count)])
      do {
        let data = try await fetch("quote", ["symbol": chunk.joined(separator: ","), "timezone": "UTC"])
        result += try TwelveDataDecoding.quotes(from: data, requested: chunk, now: now())
      } catch {
        let mapped = try MarketDataError(error) // cancellation stays a CancellationError
        if chunk.count == 1, mapped == .notFound {
          skippedUnknown = true
          continue
        }
        guard !result.isEmpty else {
          throw mapped
        }
        Log.network.info("Twelve Data chunk failed after \(result.count) quotes: \(mapped.userMessage)")
        throw PartialQuotesError(quotes: result, underlying: mapped)
      }
    }
    if result.isEmpty, skippedUnknown {
      throw MarketDataError.notFound
    }
    return result
  }

  func series(_ symbol: String, range: ChartRange) async throws -> PriceSeries {
    let parameters = Self.parameters(for: range)
    let data = try await fetch("time_series", [
      "symbol": symbol,
      "interval": parameters.interval,
      "outputsize": String(parameters.outputSize),
      "timezone": "UTC",
    ])
    var points = try TwelveDataDecoding.points(from: data)
    if range == .oneDay {
      points = TwelveDataDecoding.lastSession(points)
    }
    return PriceSeries(symbol: symbol.uppercased(), range: range, points: points, asOf: points.last?.date ?? now())
  }

  func search(_ query: String) async throws -> [SymbolSearchResult] {
    let data = try await fetch("symbol_search", ["symbol": query, "outputsize": "30"])
    return try TwelveDataDecoding.search(from: data)
  }

  // MARK: Private

  private func url(_ path: String, _ parameters: [String: String]) -> URL {
    var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
    components.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
      + [URLQueryItem(name: "apikey", value: apiKey)]
    // URLComponents leaves `+` as is, and a server may read it as a space. Encoded values never contain a literal `+` otherwise.
    components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    return components.url!
  }

  private func fetch(_ path: String, _ parameters: [String: String]) async throws -> Data {
    let (data, response) = try await get(url(path, parameters))
    if response.statusCode == 429 {
      throw MarketDataError.rateLimited(retryAfter: .seconds(60))
    }
    guard (200 ..< 300).contains(response.statusCode) else {
      throw MarketDataError.network("HTTP \(response.statusCode)")
    }
    // Twelve Data reports errors (including 429) as HTTP 200 with a top-level {code, message, status: "error"}.
    if let error = try? JSONDecoder().decode(TDError.self, from: data), error.status == "error" {
      throw error.marketDataError
    }
    return data
  }
}
