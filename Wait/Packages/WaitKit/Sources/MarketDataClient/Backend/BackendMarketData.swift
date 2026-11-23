//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import APIClient
import Dependencies
import Domain
import Foundation
import Logging

// MARK: - MarketDataClient + Backend

extension MarketDataClient {
  /// The server accepts at most 50 symbols per `/api/market/quotes` call (overview §8.4).
  static let maxSymbolsPerRequest = 50

  /// Uppercased, deduped, and only tickers the server's symbol rule accepts. Others (e.g. `0700.HK`)
  /// are never sent; callers see them as missing rather than failing the whole batch with a 400.
  static func requestableSymbols(_ symbols: [String]) -> [String] {
    var seen = Set<String>()
    return symbols
      .map { $0.uppercased() }
      .filter { $0.range(of: #"^[A-Z]{1,5}([.-][A-Z]{1,2})?$"#, options: .regularExpression) != nil && seen.insert($0).inserted }
  }

  /// Every call goes to the Wait backend, which owns provider keys, shared caches and rate limits.
  /// Wrap it with `.cached(_:disk:ttl:now:)` for on-device TTLs, coalescing and the 429 cooldown.
  public static func backend(_ api: APIClient) -> MarketDataClient {
    MarketDataClient(
      quotes: { symbols, _ in
        let requestable = requestableSymbols(symbols)
        guard !requestable.isEmpty else {
          return []
        }
        return try await mapAPIErrors {
          var quotes: [Quote] = []
          for start in stride(from: 0, to: requestable.count, by: maxSymbolsPerRequest) {
            let chunk = Array(requestable[start ..< min(start + maxSymbolsPerRequest, requestable.count)])
            do {
              quotes += try await api.quotes(chunk).quotes.compactMap(Quote.init(dto:))
            } catch let error as APIError where !quotes.isEmpty && (error.status == 429 || error.status == 503) {
              // A later chunk hit the limit: hand back what we have (plan 02's PartialQuotesError contract).
              throw PartialQuotesError(quotes: quotes, retryAfter: error.retryAfter)
            }
          }
          return quotes
        }
      },
      series: { symbol, range, _ in
        try await mapAPIErrors { try PriceSeries(dto: try await api.history(symbol, range)) }
      },
      search: { query in
        // The server accepts 1–30 characters with at least one non-space.
        let trimmed = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        guard !trimmed.isEmpty else {
          return []
        }
        return try await mapAPIErrors { try await api.search(trimmed).results.map(SymbolSearchResult.init(dto:)) }
      },
      profile: { symbol in
        try await mapAPIErrors { CompanyProfile(dto: try await api.profile(symbol)) }
      }
    )
  }
}

// MARK: - MarketDataError + APIError

extension MarketDataError {
  init(apiError: APIError) {
    switch apiError.status {
      case 429, 503: self = .rateLimited(retryAfter: apiError.retryAfter)
      case 404: self = .notFound
      case 0 where apiError.isConfigurationFailure: self = .unavailable
      case 0: self = .network(apiError.message)
      default: self = apiError.code == "DECODING" ? .decoding(apiError.message) : .unavailable
    }
  }
}

/// A misconfigured base URL or an unreadable anonymous ID fails every call the same way. Log each code once, not once per call.
private enum ConfigurationFailureLog {
  static func record(_ error: APIError) {
    guard error.isConfigurationFailure, reported.withValue({ $0.insert(error.code).inserted }) else {
      return
    }
    Log.network.error("Backend unavailable (\(error.code)): \(error.message)")
  }

  private static let reported = LockIsolated<Set<String>>([])
}

private func mapAPIErrors<T>(_ work: () async throws -> T) async throws -> T {
  do {
    return try await work()
  } catch let error as APIError {
    ConfigurationFailureLog.record(error)
    throw MarketDataError(apiError: error)
  } catch let partial as PartialQuotesError {
    throw partial // the decorator keeps partial.quotes and starts the cooldown
  } catch {
    throw try MarketDataError(error) // rethrows cancellation unchanged
  }
}

// MARK: - DTO → Domain

extension Quote {
  /// Nil when the price is not a plain decimal literal; such rows are dropped, never shown as 0.
  init?(dto: QuoteDTO) {
    guard let price = DecimalCoding.parse(dto.price) else {
      return nil
    }
    self.init(
      symbol: dto.symbol,
      price: price,
      previousClose: dto.previousClose.flatMap(DecimalCoding.parse),
      open: dto.open.flatMap(DecimalCoding.parse),
      high: dto.high.flatMap(DecimalCoding.parse),
      low: dto.low.flatMap(DecimalCoding.parse),
      change: dto.change.flatMap(DecimalCoding.parse),
      changePercent: dto.changePercent,
      volume: dto.volume,
      fiftyTwoWeekHigh: dto.fiftyTwoWeekHigh.flatMap(DecimalCoding.parse),
      fiftyTwoWeekLow: dto.fiftyTwoWeekLow.flatMap(DecimalCoding.parse),
      asOf: dto.asOf,
      isStale: dto.stale
    )
  }
}

extension PriceSeries {
  init(dto: HistoryResponseDTO) throws {
    guard let range = ChartRange(rawValue: dto.range) else { throw MarketDataError.decoding("Unknown chart range \(dto.range)") }
    self.init(
      symbol: dto.symbol,
      range: range,
      points: dto.points.compactMap { point in DecimalCoding.parse(point.c).map { PricePoint(date: point.t, close: $0) } },
      asOf: dto.asOf,
      delayedMinutes: dto.delayedMinutes,
      isStale: dto.stale
    )
  }
}

extension SymbolSearchResult {
  init(dto: SearchResultDTO) {
    self.init(symbol: dto.symbol, name: dto.name, exchange: dto.exchange, type: dto.type)
  }
}

extension CompanyProfile {
  init(dto: ProfileDTO) {
    self.init(
      symbol: dto.symbol,
      name: dto.name,
      exchange: dto.exchange,
      industry: dto.industry,
      logoURL: dto.logoUrl.flatMap(URL.init(string:)),
      marketCap: dto.marketCap.flatMap(DecimalCoding.parse),
      peRatio: dto.peRatio,
      pbRatio: dto.pbRatio,
      dividendYield: dto.dividendYield,
      roe: dto.roe,
      roa: dto.roa,
      profitMargin: dto.profitMargin,
      fiftyTwoWeekHigh: dto.fiftyTwoWeekHigh.flatMap(DecimalCoding.parse),
      fiftyTwoWeekLow: dto.fiftyTwoWeekLow.flatMap(DecimalCoding.parse),
      beta: dto.beta,
      asOf: dto.asOf
    )
  }
}
