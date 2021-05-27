// Created by kai_chen on 5/4/21.

import Foundation
import Money

struct Stock: Codable, Equatable {
  let symbol: String
  let name: String
  let currentPrice: Money<USD>
  let expectedPrice: Money<USD>
  let changePercent: String
}
