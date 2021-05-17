// Created by kai_chen on 5/16/21.
// Copyright © 2021 Airbnb Inc. All rights reserved.

import Foundation

// MARK: - URLDomain

enum URLDomain: String {
  case alphaVantage = "https://www.alphavantage.co"
}

extension URLDomain {
  var queryItems: [URLQueryItem] {
    switch self {
      case .alphaVantage:
        let apiKeyItem = URLQueryItem(name: "apikey", value: "L51Y2HE61NU1YU0G")
        return [apiKeyItem]
    }
  }
}