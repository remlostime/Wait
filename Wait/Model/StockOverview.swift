//
// Created by: kai_chen on 6/6/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

public struct StockOverview: Decodable {
  enum CodingKeys: String, CodingKey {
    case PERatio
    case PBRatio = "PriceToBookRatio"
    case marketCap = "MarketCapitalization"
    case dividendPerShare = "DividendPerShare"
  }

  public let PERatio: String
  public let PBRatio: String
  public let marketCap: String
  public let dividendPerShare: String
}
