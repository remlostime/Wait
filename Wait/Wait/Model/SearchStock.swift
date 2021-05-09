// Created by kai_chen on 5/9/21.
// Copyright © 2021 Airbnb Inc. All rights reserved.

import Foundation

struct SearchStock: Decodable {
  enum CodingKeys: String, CodingKey {
    case symbol = "1. symbol"
    case name = "2. name"
    case region = "4. region"
    case matchScore = "9. matchScore"
  }

  let symbol: String
  let name: String
  let matchScore: String
  let region: String
}
