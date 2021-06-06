// Created by kai_chen on 5/8/21.

import Foundation
import Money

struct StockCurrentQuote: Codable {
  let symbol: String
  let name: String
  let open: Money<USD>
  let high: Money<USD>
  let low: Money<USD>
  let close: Money<USD>
  let volume: String
  let datetime: Date
}
