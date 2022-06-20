// Created by kai_chen on 5/19/21.

import Foundation
import Money

public struct StockQuote: Codable {
  // MARK: Public

  public let open: Money<USD>
  public let high: Money<USD>
  public let low: Money<USD>
  public let close: Money<USD>
  public let date: Date

  // MARK: Internal

  enum CodingKeys: String, CodingKey {
    case open
    case high
    case low
    case close
    case date = "datetime"
  }
}

extension StockQuote: Identifiable {
  public var id: Date {
    date
  }
}
