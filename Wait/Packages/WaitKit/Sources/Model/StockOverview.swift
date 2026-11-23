//
// Created by: kai_chen on 6/6/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import Money

// MARK: - StockOverview

public struct StockOverview: Decodable, Equatable {
  // MARK: Lifecycle

  public init(
    name: String,
    description: String,
    PERatio: String,
    PBRatio: String,
    PEGRatio: String,
    marketCap: Money<USD>,
    dividendPerShare: String,
    profitMargin: String,
    weekHigh52: String,
    weekLow52: String,
    returnOnEquity: String,
    returnOnAssets: String
  ) {
    self.name = name
    self.description = description
    self.PERatio = PERatio
    self.PBRatio = PBRatio
    self.marketCap = marketCap
    self.dividendPerShare = dividendPerShare
    self.PEGRatio = PEGRatio
    self.profitMargin = profitMargin
    self.weekLow52 = weekLow52
    self.weekHigh52 = weekHigh52
    self.returnOnEquity = returnOnEquity
    self.returnOnAssets = returnOnAssets
  }

  // MARK: Public

  public var name: String
  public var description: String
  public var PERatio: String
  public var PBRatio: String
  public var marketCap: Money<USD>
  public var dividendPerShare: String
  public var PEGRatio: String
  public var profitMargin: String
  public var weekHigh52: String
  public var weekLow52: String
  public var returnOnEquity: String
  public var returnOnAssets: String

  // MARK: Internal

  enum CodingKeys: String, CodingKey {
    case name = "Name"
    case description = "Description"
    case PERatio
    case PBRatio = "PriceToBookRatio"
    case marketCap = "MarketCapitalization"
    case dividendPerShare = "DividendPerShare"
    case PEGRatio
    case profitMargin = "ProfitMargin"
    case returnOnEquity = "ReturnOnEquityTTM"
    case returnOnAssets = "ReturnOnAssetsTTM"
    case weekHigh52 = "52WeekHigh"
    case weekLow52 = "52WeekLow"
  }
}

public extension StockOverview {
  static let empty = StockOverview(
    name: "empty",
    description: "empty",
    PERatio: "0",
    PBRatio: "0",
    PEGRatio: "0",
    marketCap: 0,
    dividendPerShare: "0",
    profitMargin: "0",
    weekHigh52: "0",
    weekLow52: "0",
    returnOnEquity: "0",
    returnOnAssets: "0"
  )
}
