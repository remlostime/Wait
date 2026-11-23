//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - WatchlistSnapshot

/// The read-only view of the watchlist that the app publishes for the widget (app group `snapshot.json`) and the watch (WCSession, plan 03).
public struct WatchlistSnapshot: Codable, Equatable, Sendable {
  // MARK: Lifecycle

  public init(generatedAt: Date, quotesAsOf: Date?, rows: [Row]) {
    self.generatedAt = generatedAt
    self.quotesAsOf = quotesAsOf
    self.rows = rows
  }

  // MARK: Public

  public struct Row: Equatable, Identifiable, Sendable {
    // MARK: Lifecycle

    public init(
      symbol: String,
      name: String,
      price: Decimal?,
      changePercent: Double?,
      status: LadderStatus?,
      temperature: Double?,
      ladder: PriceLadder,
      isFavorite: Bool
    ) {
      self.symbol = symbol
      self.name = name
      self.price = price
      self.changePercent = changePercent
      self.status = status
      self.temperature = temperature
      self.ladder = ladder
      self.isFavorite = isFavorite
    }

    // MARK: Public

    public let symbol: String
    public let name: String
    public let price: Decimal?
    public let changePercent: Double?
    public let status: LadderStatus?
    public let temperature: Double?
    public let ladder: PriceLadder
    public let isFavorite: Bool

    public var id: String {
      symbol
    }
  }

  public let generatedAt: Date
  /// The oldest quote time among the rows that have a quote.
  public let quotesAsOf: Date?
  /// Favorites first, then by `sortIndex`, then by symbol.
  public let rows: [Row]

  public static func make(items: [WatchlistItem], quotes: [String: Quote], now: Date) -> WatchlistSnapshot {
    let ordered = items.sorted { ($0.isFavorite ? 0 : 1, $0.sortIndex, $0.symbol) < ($1.isFavorite ? 0 : 1, $1.sortIndex, $1.symbol) }
    let rows = ordered.map { item in
      let quote = quotes[item.symbol]
      return Row(
        symbol: item.symbol,
        name: item.name,
        price: quote?.price,
        changePercent: quote?.changePercent,
        status: quote.map { item.ladder.status(at: $0.price) },
        temperature: quote.flatMap { item.ladder.temperature(at: $0.price)?.value },
        ladder: item.ladder,
        isFavorite: item.isFavorite
      )
    }
    let asOf = ordered.compactMap { quotes[$0.symbol]?.asOf }.min()
    return WatchlistSnapshot(generatedAt: now, quotesAsOf: asOf, rows: rows)
  }
}

// MARK: - WatchlistSnapshot.Row + Codable

extension WatchlistSnapshot.Row: Codable {
  // MARK: Lifecycle

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      symbol: c.decode(String.self, forKey: .symbol),
      name: c.decode(String.self, forKey: .name),
      price: c.decodeDecimalIfPresent(forKey: .price),
      changePercent: c.decodeIfPresent(Double.self, forKey: .changePercent),
      status: c.decodeIfPresent(LadderStatus.self, forKey: .status),
      temperature: c.decodeIfPresent(Double.self, forKey: .temperature),
      ladder: c.decodeIfPresent(PriceLadder.self, forKey: .ladder) ?? .empty,
      isFavorite: c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    )
  }

  // MARK: Public

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(symbol, forKey: .symbol)
    try c.encode(name, forKey: .name)
    try c.encodeDecimalIfPresent(price, forKey: .price)
    try c.encodeIfPresent(changePercent, forKey: .changePercent)
    try c.encodeIfPresent(status, forKey: .status)
    try c.encodeIfPresent(temperature, forKey: .temperature)
    try c.encode(ladder, forKey: .ladder)
    try c.encode(isFavorite, forKey: .isFavorite)
  }

  // MARK: Private

  private enum CodingKeys: String, CodingKey {
    case symbol, name, price, changePercent, status, temperature, ladder, isFavorite
  }
}
