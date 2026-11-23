//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// Wire DTOs for /api/market/* (overview §8.4). Prices stay decimal strings here.
// `MarketDataClient.backend` converts them to Domain types.

// MARK: - QuoteDTO

public struct QuoteDTO: Decodable, Equatable, Sendable {
  public let symbol: String
  public let price: String
  public let previousClose: String?
  public let open: String?
  public let high: String?
  public let low: String?
  public let change: String?
  public let changePercent: Double?
  public let volume: Int?
  public let fiftyTwoWeekHigh: String?
  public let fiftyTwoWeekLow: String?
  public let asOf: Date
  public let source: String
  public let stale: Bool
}

// MARK: - QuotesResponseDTO

public struct QuotesResponseDTO: Decodable, Equatable, Sendable {
  public let quotes: [QuoteDTO]
  public let missing: [String]
}

// MARK: - HistoryPointDTO

public struct HistoryPointDTO: Decodable, Equatable, Sendable {
  public let t: Date
  public let c: String
}

// MARK: - HistoryResponseDTO

public struct HistoryResponseDTO: Decodable, Equatable, Sendable {
  public let symbol: String
  public let range: String
  public let points: [HistoryPointDTO]
  public let source: String
  public let asOf: Date
  public let stale: Bool
  public let delayedMinutes: Int?
}

// MARK: - SearchResultDTO

public struct SearchResultDTO: Decodable, Equatable, Sendable {
  public let symbol: String
  public let name: String
  public let exchange: String?
  public let type: String
}

// MARK: - SearchResponseDTO

public struct SearchResponseDTO: Decodable, Equatable, Sendable {
  public let results: [SearchResultDTO]
}

// MARK: - ProfileDTO

/// Ratios follow Finnhub: dividend yield, ROE, ROA and margin are percentages (0.55 means 0.55%).
public struct ProfileDTO: Decodable, Equatable, Sendable {
  public let symbol: String
  public let name: String?
  public let exchange: String?
  public let industry: String?
  public let logoUrl: String?
  public let marketCap: String?
  public let peRatio: Double?
  public let pbRatio: Double?
  public let dividendYield: Double?
  public let roe: Double?
  public let roa: Double?
  public let profitMargin: Double?
  public let fiftyTwoWeekHigh: String?
  public let fiftyTwoWeekLow: String?
  public let beta: Double?
  public let asOf: Date
}
