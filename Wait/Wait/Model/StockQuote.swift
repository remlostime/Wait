// Created by kai_chen on 5/19/21.

import Foundation
import Money

struct StockQuote: Codable {
  // MARK: Lifecycle

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    open = try container.decode(Money<USD>.self, forKey: .open)
    high = try container.decode(Money<USD>.self, forKey: .high)
    low = try container.decode(Money<USD>.self, forKey: .low)
    close = try container.decode(Money<USD>.self, forKey: .close)
    date = Date()
  }

  init(
    open: Money<USD>,
    high: Money<USD>,
    low: Money<USD>,
    close: Money<USD>,
    date: Date
  ) {
    self.open = open
    self.high = high
    self.low = low
    self.close = close
    self.date = date
  }

  // MARK: Internal

  enum CodingKeys: String, CodingKey {
    case open = "1. open"
    case high = "2. high"
    case low = "3. low"
    case close = "4. close"
  }

  let open: Money<USD>
  let high: Money<USD>
  let low: Money<USD>
  let close: Money<USD>
  let date: Date
}
