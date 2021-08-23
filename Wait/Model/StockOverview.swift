//
// Created by: kai_chen on 6/6/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import Money

// MARK: - StockOverview

public struct StockOverview: Decodable {
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
    case PEGRatio = "PEGRatio"
    case profitMargin = "ProfitMargin"
    case returnOnEquity = "ReturnOnEquityTTM"
    case returnOnAssets = "ReturnOnAssetsTTM"
    case weekHigh52 = "52WeekHigh"
    case weekLow52 = "52WeekLow"
  }
}

public extension StockOverview {
  static let empty = StockOverview(
    name: "",
    description: "",
    PERatio: "",
    PBRatio: "",
    PEGRatio: "",
    marketCap: 0,
    dividendPerShare: "",
    profitMargin: "",
    weekHigh52: "",
    weekLow52: "",
    returnOnEquity: "",
    returnOnAssets: ""
  )
}
