//
// Created by: kai_chen on 6/6/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

struct StockOverview: Decodable {
  let PERatio: String
  let PBRatio: String
  let marketCap: String
  let dividendPerShare: String

  enum CodingKeys: String, CodingKey {
    case PERatio = "PERatio"
    case PBRatio = "PriceToBookRatio"
    case marketCap = "MarketCapitalization"
    case dividendPerShare = "DividendPerShare"
  }
}
