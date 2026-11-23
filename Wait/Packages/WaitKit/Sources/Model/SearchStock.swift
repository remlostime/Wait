// Created by kai_chen on 5/9/21.
// Copyright © 2021 Airbnb Inc. All rights reserved.

import Foundation

// MARK: - SearchStockResult

public struct SearchStockResult: Decodable {
  // MARK: Lifecycle

  public init(
    symbol: String,
    name: String,
    exchange: String,
    country: String,
    currency: String
  ) {
    self.symbol = symbol
    self.name = name
    self.exchange = exchange
    self.country = country
    self.currency = currency
  }

  // MARK: Public

  public let symbol: String
  public let name: String
  public let exchange: String
  public let country: String
  public let currency: String

  // MARK: Internal

  enum CodingKeys: String, CodingKey {
    case symbol
    case name = "instrument_name"
    case exchange
    case country
    case currency
  }
}

// MARK: - SearchStockResults

public struct SearchStockResults: Decodable {
  public let data: [SearchStockResult]
}
