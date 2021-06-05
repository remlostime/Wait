// Created by kai_chen on 5/9/21.
// Copyright © 2021 Airbnb Inc. All rights reserved.

import Foundation

struct SearchStockResult: Decodable {
  enum CodingKeys: String, CodingKey {
    case symbol
    case name = "instrument_name"
    case exchange
    case country
    case currency
  }

  let symbol: String
  let name: String
  let exchange: String
  let country: String
  let currency: String
}
