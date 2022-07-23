//
// Created by: Kai Chen on 7/23/22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import Money

struct StockCurrentQuote: Codable {
  // MARK: Lifecycle

  init(
    symbol: String,
    name: String,
    open: Money<USD>,
    high: Money<USD>,
    low: Money<USD>,
    close: Money<USD>,
    volume: String,
    datetime: Date,
    percentChange: String
  ) {
    self.symbol = symbol
    self.name = name
    self.open = open
    self.high = high
    self.low = low
    self.close = close
    self.volume = volume
    self.datetime = datetime
    self.percentChange = percentChange
  }

  // MARK: Public

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
