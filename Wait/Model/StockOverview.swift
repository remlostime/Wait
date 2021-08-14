//
// Created by: kai_chen on 6/6/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import Money

public struct StockOverview: Decodable {
  // MARK: Lifecycle

  public init(
    name: String,
    description: String,
    PERatio: String,
    PBRatio: String,
    marketCap: Money<USD>,
    dividendPerShare: String
  ) {
    self.name = name
    self.description = description
    self.PERatio = PERatio
    self.PBRatio = PBRatio
    self.marketCap = marketCap
    self.dividendPerShare = dividendPerShare
  }

  // MARK: Public

  public var name: String
  public var description: String
  public var PERatio: String
  public var PBRatio: String
  public var marketCap: Money<USD>
  public var dividendPerShare: String

  // MARK: Internal

  enum CodingKeys: String, CodingKey {
    case name = "Name"
    case description = "Description"
    case PERatio
    case PBRatio = "PriceToBookRatio"
    case marketCap = "MarketCapitalization"
    case dividendPerShare = "DividendPerShare"
  }
}

extension StockOverview {
  public static let empty = StockOverview(
    name: "",
    description: "",
    PERatio: "",
    PBRatio: "",
    marketCap: 0,
    dividendPerShare: ""
  )
}
