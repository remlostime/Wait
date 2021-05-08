// Created by kai_chen on 5/8/21.
// Copyright © 2021 Airbnb Inc. All rights reserved.

import Foundation

struct StockQuote: Decodable {
//  let date: Date

  enum CodingKeys: String, CodingKey {
    case symbol = "01. symbol"
    case price = "05. price"
//    case date = "07. latest trading day"
  }

  let symbol: String
  let price: String
}
