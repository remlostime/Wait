//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation

// MARK: - TDError

struct TDError: Decodable {
  let code: Int
  let message: String
  let status: String

  var marketDataError: MarketDataError {
    switch code {
      case 429: .rateLimited(retryAfter: .seconds(60))
      case 404: .notFound
      case 400 where message.localizedCaseInsensitiveContains("not found"): .notFound
      default: .network(message)
    }
  }
}

// MARK: - TDQuote

struct TDQuote: Decodable {
  struct Range: Decodable {
    let low: String?
    let high: String?
  }

  enum CodingKeys: String, CodingKey {
    case timestamp, open, high, low, close, volume, change, code
    case previousClose = "previous_close"
    case percentChange = "percent_change"
    case fiftyTwoWeek = "fifty_two_week"
  }

  let timestamp: Int?
  let open: String?
  let high: String?
  let low: String?
  let close: String?
  let volume: String?
  let change: String?
  let code: Int?
  let previousClose: String?
  let percentChange: String?
  let fiftyTwoWeek: Range?

  func quote(symbol: String) -> Quote? {
    guard code == nil, let price = close.flatMap(DecimalCoding.parse) else {
      return nil
    }
    return Quote(
      symbol: symbol.uppercased(),
      price: price,
      previousClose: previousClose.flatMap(DecimalCoding.parse),
      open: open.flatMap(DecimalCoding.parse),
      high: high.flatMap(DecimalCoding.parse),
      low: low.flatMap(DecimalCoding.parse),
      change: change.flatMap(DecimalCoding.parse),
      changePercent: percentChange.flatMap(Double.init),
      volume: volume.flatMap(Int.init),
      fiftyTwoWeekHigh: fiftyTwoWeek?.high.flatMap(DecimalCoding.parse),
      fiftyTwoWeekLow: fiftyTwoWeek?.low.flatMap(DecimalCoding.parse),
      asOf: timestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
    )
  }
}

// MARK: - LossyTDQuote

struct LossyTDQuote: Decodable {
  let value: TDQuote?

  init(from decoder: any Decoder) throws {
    value = try? TDQuote(from: decoder)
  }
}

// MARK: - TDTimeSeries

struct TDTimeSeries: Decodable {
  struct Bar: Decodable {
    let datetime: String
    let close: String
  }

  let values: [Bar]?
}

// MARK: - TDSearch

struct TDSearch: Decodable {
  struct Item: Decodable {
    enum CodingKeys: String, CodingKey {
      case symbol, exchange, country
      case instrumentName = "instrument_name"
      case instrumentType = "instrument_type"
    }

    let symbol: String
    let exchange: String?
    let country: String?
    let instrumentName: String
    let instrumentType: String?
  }

  let data: [Item]
}

// MARK: - TwelveDataDecoding

enum TwelveDataDecoding {
  static let searchableTypes: Set<String> = ["Common Stock", "ETF", "REIT", "Depositary Receipt"]

  static func quotes(from data: Data, requested: [String]) throws -> [Quote] {
    let decoder = JSONDecoder()
    if requested.count == 1 {
      return try decoder.decode(TDQuote.self, from: data).quote(symbol: requested[0]).map { [$0] } ?? []
    }
    // Lossy per symbol: one garbage entry (wrong type, missing fields) mustn't fail the whole batch.
    let batch = try decoder.decode([String: LossyTDQuote].self, from: data)
    return requested.compactMap { symbol in (batch[symbol] ?? batch[symbol.uppercased()])?.value?.quote(symbol: symbol) }
  }

  /// `timezone=UTC` is always requested. Date-only bars are anchored at 12:00 UTC so US time zones show the same calendar day.
  static func points(from data: Data) throws -> [PricePoint] {
    let series = try JSONDecoder().decode(TDTimeSeries.self, from: data)
    let dateTime = DateFormatter()
    dateTime.locale = Locale(identifier: "en_US_POSIX")
    dateTime.timeZone = TimeZone(identifier: "UTC")
    dateTime.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let dateOnly = DateFormatter()
    dateOnly.locale = Locale(identifier: "en_US_POSIX")
    dateOnly.timeZone = TimeZone(identifier: "UTC")
    dateOnly.dateFormat = "yyyy-MM-dd"
    return (series.values ?? [])
      .compactMap { bar -> PricePoint? in
        let date = dateTime.date(from: bar.datetime) ?? dateOnly.date(from: bar.datetime).map { $0.addingTimeInterval(12 * 3600) }
        guard let date, let close = DecimalCoding.parse(bar.close) else {
          return nil
        }
        return PricePoint(date: date, close: close)
      }
      .sorted { $0.date < $1.date }
  }

  /// Keeps only the points on the same New York calendar day as the newest point.
  static func lastSession(_ points: [PricePoint]) -> [PricePoint] {
    guard let last = points.last else {
      return []
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = MarketCalendar.timeZone
    return points.filter { calendar.isDate($0.date, inSameDayAs: last.date) }
  }

  static func search(from data: Data) throws -> [SymbolSearchResult] {
    let response = try JSONDecoder().decode(TDSearch.self, from: data)
    var seen = Set<String>()
    return response.data
      .filter { $0.country == "United States" && Self.searchableTypes.contains($0.instrumentType ?? "") }
      .filter { seen.insert($0.symbol).inserted }
      .map { SymbolSearchResult(symbol: $0.symbol, name: $0.instrumentName, exchange: $0.exchange, type: $0.instrumentType) }
  }
}
