// Created by kai_chen on 5/19/21.

import Foundation
import Money

public struct StockQuote: Codable {
  enum CodingKeys: String, CodingKey {
    case open
    case high
    case low
    case close
    case date = "datetime"
  }

  public let open: Money<USD>
  public let high: Money<USD>
  public let low: Money<USD>
  public let close: Money<USD>
  public let date: Date
}
