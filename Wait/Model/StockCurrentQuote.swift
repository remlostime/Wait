// Created by kai_chen on 5/8/21.

import Foundation
import Money

public struct StockCurrentQuote: Codable {
  public let symbol: String
  public let name: String
  public let open: Money<USD>
  public let high: Money<USD>
  public let low: Money<USD>
  public let close: Money<USD>
  public let volume: String
  public let datetime: Date
  public let percentChange: String
}
