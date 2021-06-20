// Created by kai_chen on 5/16/21.
// Copyright © 2021 Airbnb Inc. All rights reserved.

import Foundation

// MARK: - URLDomain

public enum URLDomain: String {
  case alphaVantage = "https://www.alphavantage.co"
  case twelveData = "https://api.twelvedata.com"
}

public extension URLDomain {
  var queryItems: [URLQueryItem] {
    switch self {
      case .alphaVantage:
        let apiKeyItem = URLQueryItem(name: "apikey", value: "L51Y2HE61NU1YU0G")
        return [apiKeyItem]
      case .twelveData:
        let apiKeyItem = URLQueryItem(name: "apikey", value: "58c41ef6d56249e5921d89f4b0c55fef")
        return [apiKeyItem]
    }
  }
}
