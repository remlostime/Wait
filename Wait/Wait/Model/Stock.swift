// Created by kai_chen on 5/4/21.

import Foundation

struct Stock: Codable {
  let ticker: String
  let name: String
  let currentPrice: Double
  let expectedPrice: Double
}
