// Created by kai_chen on 5/8/21.

import Foundation
import Money

struct StockQuote: Decodable {
  enum CodingKeys: String, CodingKey {
    case symbol = "01. symbol"
    case price = "05. price"
    case date = "07. latest trading day"
    case changePercent = "10. change percent"
  }

  let symbol: String
  let price: Money<USD>
  let changePercent: String
  let date: Date
}
