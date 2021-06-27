//
// Created by: kai_chen on 6/6/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

public struct StockOverview: Decodable {
  // MARK: Public

  public var name: String
  public var description: String
  public var PERatio: String
  public var PBRatio: String
  public var marketCap: String
  public var dividendPerShare: String

  public init(
    name: String,
    description: String,
    PERatio: String,
    PBRatio: String,
    marketCap: String,
    dividendPerShare: String
  ) {
    self.name = name
    self.description = description
    self.PERatio = PERatio
    self.PBRatio = PBRatio
    self.marketCap = marketCap
    self.dividendPerShare = dividendPerShare
  }

  // MARK: Internal

  enum CodingKeys: String, CodingKey {
    case name = "Name"
    case description = "Description"
    case PERatio = "PERatio"
    case PBRatio = "PriceToBookRatio"
    case marketCap = "MarketCapitalization"
    case dividendPerShare = "DividendPerShare"
  }
}
