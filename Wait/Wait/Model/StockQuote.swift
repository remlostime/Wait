// Created by kai_chen on 5/19/21.

import Foundation
import Money

struct StockQuote: Codable {
  enum CodingKeys: String, CodingKey {
    case open
    case high
    case low
    case close
    case date = "datetime"
  }

  let open: Money<USD>
  let high: Money<USD>
  let low: Money<USD>
  let close: Money<USD>
  let date: Date
}
