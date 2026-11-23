// Created by kai_chen on 5/16/21.
// Copyright © 2021 Wait. All rights reserved.

import Foundation

// MARK: - URLDomain

public enum URLDomain: String {
  case twelveData = "https://api.twelvedata.com"
}

public extension URLDomain {
  var queryItems: [URLQueryItem] {
    switch self {
      case .twelveData:
        return [URLQueryItem(name: "apikey", value: APIKey.twelveData)]
    }
  }
}

// MARK: - APIKey

/// Provider keys injected at build time: `Config/Secrets.xcconfig` → build setting → Info.plist.
enum APIKey {
  static var twelveData: String {
    Bundle.main.object(forInfoDictionaryKey: "TwelveDataAPIKey") as? String ?? ""
  }
}
