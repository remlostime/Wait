//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - ChartRange

/// Raw values match the server `range` query parameter (overview §7.1).
public enum ChartRange: String, CaseIterable, Codable, Hashable, Sendable {
  case oneDay = "1D"
  case oneWeek = "1W"
  case oneMonth = "1M"
  case oneYear = "1Y"
  case fiveYears = "5Y"

  // MARK: Public

  public var title: String {
    rawValue
  }
}

// MARK: - Quote

public struct Quote: Equatable, Sendable {
  // MARK: Lifecycle

  public init(
    symbol: String,
    price: Decimal,
    previousClose: Decimal? = nil,
    open: Decimal? = nil,
    high: Decimal? = nil,
    low: Decimal? = nil,
    change: Decimal? = nil,
    changePercent: Double? = nil,
    volume: Int? = nil,
    fiftyTwoWeekHigh: Decimal? = nil,
    fiftyTwoWeekLow: Decimal? = nil,
    asOf: Date,
    isStale: Bool = false
  ) {
    self.symbol = symbol
    self.price = price
    self.previousClose = previousClose
    self.open = open
    self.high = high
    self.low = low
    self.change = change
    self.changePercent = changePercent
    self.volume = volume
    self.fiftyTwoWeekHigh = fiftyTwoWeekHigh
    self.fiftyTwoWeekLow = fiftyTwoWeekLow
    self.asOf = asOf
    self.isStale = isStale
  }

  // MARK: Public

  public let symbol: String
  public let price: Decimal
  public let previousClose: Decimal?
  public let open: Decimal?
  public let high: Decimal?
  public let low: Decimal?
  public let change: Decimal?
  public let changePercent: Double?
  public let volume: Int?
  public let fiftyTwoWeekHigh: Decimal?
  public let fiftyTwoWeekLow: Decimal?
  public let asOf: Date
  public let isStale: Bool

  public func with(isStale: Bool) -> Quote {
    Quote(
      symbol: symbol, price: price, previousClose: previousClose, open: open, high: high, low: low, change: change,
      changePercent: changePercent, volume: volume, fiftyTwoWeekHigh: fiftyTwoWeekHigh, fiftyTwoWeekLow: fiftyTwoWeekLow,
      asOf: asOf, isStale: isStale
    )
  }
}

// MARK: Codable

extension Quote: Codable {
  // MARK: Lifecycle

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      symbol: c.decode(String.self, forKey: .symbol),
      price: c.decodeDecimal(forKey: .price),
      previousClose: c.decodeDecimalIfPresent(forKey: .previousClose),
      open: c.decodeDecimalIfPresent(forKey: .open),
      high: c.decodeDecimalIfPresent(forKey: .high),
      low: c.decodeDecimalIfPresent(forKey: .low),
      change: c.decodeDecimalIfPresent(forKey: .change),
      changePercent: c.decodeIfPresent(Double.self, forKey: .changePercent),
      volume: c.decodeIfPresent(Int.self, forKey: .volume),
      fiftyTwoWeekHigh: c.decodeDecimalIfPresent(forKey: .fiftyTwoWeekHigh),
      fiftyTwoWeekLow: c.decodeDecimalIfPresent(forKey: .fiftyTwoWeekLow),
      asOf: c.decode(Date.self, forKey: .asOf),
      isStale: c.decodeIfPresent(Bool.self, forKey: .isStale) ?? false
    )
  }

  // MARK: Public

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(symbol, forKey: .symbol)
    try c.encodeDecimal(price, forKey: .price)
    try c.encodeDecimalIfPresent(previousClose, forKey: .previousClose)
    try c.encodeDecimalIfPresent(open, forKey: .open)
    try c.encodeDecimalIfPresent(high, forKey: .high)
    try c.encodeDecimalIfPresent(low, forKey: .low)
    try c.encodeDecimalIfPresent(change, forKey: .change)
    try c.encodeIfPresent(changePercent, forKey: .changePercent)
    try c.encodeIfPresent(volume, forKey: .volume)
    try c.encodeDecimalIfPresent(fiftyTwoWeekHigh, forKey: .fiftyTwoWeekHigh)
    try c.encodeDecimalIfPresent(fiftyTwoWeekLow, forKey: .fiftyTwoWeekLow)
    try c.encode(asOf, forKey: .asOf)
    try c.encode(isStale, forKey: .isStale)
  }

  // MARK: Private

  private enum CodingKeys: String, CodingKey {
    case symbol, price, previousClose, open, high, low, change, changePercent, volume, fiftyTwoWeekHigh, fiftyTwoWeekLow, asOf, isStale
  }
}

// MARK: - PricePoint

public struct PricePoint: Equatable, Sendable {
  // MARK: Lifecycle

  public init(date: Date, close: Decimal) {
    self.date = date
    self.close = close
  }

  // MARK: Public

  public let date: Date
  public let close: Decimal
}

// MARK: Codable

extension PricePoint: Codable {
  // MARK: Lifecycle

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(date: c.decode(Date.self, forKey: .date), close: c.decodeDecimal(forKey: .close))
  }

  // MARK: Public

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(date, forKey: .date)
    try c.encodeDecimal(close, forKey: .close)
  }

  // MARK: Private

  private enum CodingKeys: String, CodingKey {
    case date, close
  }
}

// MARK: - PriceSeries

public struct PriceSeries: Codable, Equatable, Sendable {
  // MARK: Lifecycle

  public init(symbol: String, range: ChartRange, points: [PricePoint], asOf: Date, delayedMinutes: Int? = nil, isStale: Bool = false) {
    self.symbol = symbol
    self.range = range
    self.points = points
    self.asOf = asOf
    self.delayedMinutes = delayedMinutes
    self.isStale = isStale
  }

  // MARK: Public

  public let symbol: String
  public let range: ChartRange
  /// Oldest first.
  public let points: [PricePoint]
  public let asOf: Date
  public let delayedMinutes: Int?
  public let isStale: Bool

  public func with(isStale: Bool) -> PriceSeries {
    PriceSeries(symbol: symbol, range: range, points: points, asOf: asOf, delayedMinutes: delayedMinutes, isStale: isStale)
  }
}

// MARK: Decodable

extension PriceSeries {
  /// `delayedMinutes` and `isStale` are optional, so older cache entries and server payloads without them still decode.
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      symbol: c.decode(String.self, forKey: .symbol),
      range: c.decode(ChartRange.self, forKey: .range),
      points: c.decode([PricePoint].self, forKey: .points),
      asOf: c.decode(Date.self, forKey: .asOf),
      delayedMinutes: c.decodeIfPresent(Int.self, forKey: .delayedMinutes),
      isStale: c.decodeIfPresent(Bool.self, forKey: .isStale) ?? false
    )
  }

  private enum CodingKeys: String, CodingKey {
    case symbol, range, points, asOf, delayedMinutes, isStale
  }
}

// MARK: - SymbolSearchResult

public struct SymbolSearchResult: Codable, Equatable, Identifiable, Sendable {
  // MARK: Lifecycle

  public init(symbol: String, name: String, exchange: String? = nil, type: String? = nil) {
    self.symbol = symbol
    self.name = name
    self.exchange = exchange
    self.type = type
  }

  // MARK: Public

  public let symbol: String
  public let name: String
  public let exchange: String?
  public let type: String?

  public var id: String {
    symbol
  }
}

// MARK: - CompanyProfile

/// Fundamentals. Plan 02 has no source for these (Twelve Data stopgap). Plan 04 fills them from the backend.
public struct CompanyProfile: Equatable, Sendable {
  // MARK: Lifecycle

  public init(
    symbol: String,
    name: String? = nil,
    exchange: String? = nil,
    industry: String? = nil,
    logoURL: URL? = nil,
    marketCap: Decimal? = nil,
    peRatio: Double? = nil,
    pbRatio: Double? = nil,
    dividendYield: Double? = nil,
    roe: Double? = nil,
    roa: Double? = nil,
    profitMargin: Double? = nil,
    fiftyTwoWeekHigh: Decimal? = nil,
    fiftyTwoWeekLow: Decimal? = nil,
    beta: Double? = nil,
    asOf: Date
  ) {
    self.symbol = symbol
    self.name = name
    self.exchange = exchange
    self.industry = industry
    self.logoURL = logoURL
    self.marketCap = marketCap
    self.peRatio = peRatio
    self.pbRatio = pbRatio
    self.dividendYield = dividendYield
    self.roe = roe
    self.roa = roa
    self.profitMargin = profitMargin
    self.fiftyTwoWeekHigh = fiftyTwoWeekHigh
    self.fiftyTwoWeekLow = fiftyTwoWeekLow
    self.beta = beta
    self.asOf = asOf
  }

  // MARK: Public

  public let symbol: String
  public let name: String?
  public let exchange: String?
  public let industry: String?
  public let logoURL: URL?
  public let marketCap: Decimal?
  public let peRatio: Double?
  public let pbRatio: Double?
  public let dividendYield: Double?
  public let roe: Double?
  public let roa: Double?
  public let profitMargin: Double?
  public let fiftyTwoWeekHigh: Decimal?
  public let fiftyTwoWeekLow: Decimal?
  public let beta: Double?
  public let asOf: Date
}

// MARK: Codable

extension CompanyProfile: Codable {
  // MARK: Lifecycle

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      symbol: c.decode(String.self, forKey: .symbol),
      name: c.decodeIfPresent(String.self, forKey: .name),
      exchange: c.decodeIfPresent(String.self, forKey: .exchange),
      industry: c.decodeIfPresent(String.self, forKey: .industry),
      logoURL: c.decodeIfPresent(URL.self, forKey: .logoURL),
      marketCap: c.decodeDecimalIfPresent(forKey: .marketCap),
      peRatio: c.decodeIfPresent(Double.self, forKey: .peRatio),
      pbRatio: c.decodeIfPresent(Double.self, forKey: .pbRatio),
      dividendYield: c.decodeIfPresent(Double.self, forKey: .dividendYield),
      roe: c.decodeIfPresent(Double.self, forKey: .roe),
      roa: c.decodeIfPresent(Double.self, forKey: .roa),
      profitMargin: c.decodeIfPresent(Double.self, forKey: .profitMargin),
      fiftyTwoWeekHigh: c.decodeDecimalIfPresent(forKey: .fiftyTwoWeekHigh),
      fiftyTwoWeekLow: c.decodeDecimalIfPresent(forKey: .fiftyTwoWeekLow),
      beta: c.decodeIfPresent(Double.self, forKey: .beta),
      asOf: c.decode(Date.self, forKey: .asOf)
    )
  }

  // MARK: Public

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(symbol, forKey: .symbol)
    try c.encodeIfPresent(name, forKey: .name)
    try c.encodeIfPresent(exchange, forKey: .exchange)
    try c.encodeIfPresent(industry, forKey: .industry)
    try c.encodeIfPresent(logoURL, forKey: .logoURL)
    try c.encodeDecimalIfPresent(marketCap, forKey: .marketCap)
    try c.encodeIfPresent(peRatio, forKey: .peRatio)
    try c.encodeIfPresent(pbRatio, forKey: .pbRatio)
    try c.encodeIfPresent(dividendYield, forKey: .dividendYield)
    try c.encodeIfPresent(roe, forKey: .roe)
    try c.encodeIfPresent(roa, forKey: .roa)
    try c.encodeIfPresent(profitMargin, forKey: .profitMargin)
    try c.encodeDecimalIfPresent(fiftyTwoWeekHigh, forKey: .fiftyTwoWeekHigh)
    try c.encodeDecimalIfPresent(fiftyTwoWeekLow, forKey: .fiftyTwoWeekLow)
    try c.encodeIfPresent(beta, forKey: .beta)
    try c.encode(asOf, forKey: .asOf)
  }

  // MARK: Private

  private enum CodingKeys: String, CodingKey {
    case symbol, name, exchange, industry, logoURL, marketCap, peRatio, pbRatio, dividendYield, roe, roa, profitMargin
    case fiftyTwoWeekHigh, fiftyTwoWeekLow, beta, asOf
  }
}
