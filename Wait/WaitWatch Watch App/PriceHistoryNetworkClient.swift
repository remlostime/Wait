//
// Created by: Kai Chen on 7/23/22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import SwiftyJSON
import Alamofire

class PriceHistoryNetworkClient {
  // MARK: Internal

  func fetchHistory(
    symbol: String,
    timeSection: TimeSection,
    completion: @escaping (([StockQuote]) -> Void)
  ) {
    guard let url = makeHistoryURL(symbol: symbol, timeSection: timeSection) else {
      return
    }

    AF.request(url).validate().responseData { response in
      switch response.result {
        case let .success(data):
          let decoder = JSONDecoder()
          decoder.dateDecodingStrategy = .formatted(timeSection.dateFormatter)

          guard
            let json = try? JSON(data: data),
            let rawData = try? json["values"].rawData()
          else {
            return
          }

          do {
            let stockQuotes = try decoder.decode([StockQuote].self, from: rawData)
            completion(stockQuotes.reversed())
          } catch {
            completion([])
          }
        case let .failure(error):
          completion([])
      }
    }
  }

  // MARK: Private

  private func makeHistoryURL(symbol: String, timeSection: TimeSection) -> URL? {
    let priceHistoryAPIParams = [
      "symbol": symbol,
      "outputsize": String(timeSection.dataSize),
      "interval": timeSection.dataInterval,
    ]

    let url = NetworkingURLBuilder.buildURL(api: "time_series", params: priceHistoryAPIParams)

    return url
  }
}

public enum NetworkingURLBuilder {
  public static func buildURL(
    domain: URLDomain = .twelveData,
    api: String,
    params: [String: String?]? = nil
  ) -> URL? {
    guard let url = URL(string: api, relativeTo: URL(string: domain.rawValue)) else {
      return nil
    }

    var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true)

    var finalQueryItems = domain.queryItems

    if let params = params {
      let queryItems: [URLQueryItem] = params.compactMap { key, value -> URLQueryItem in
        URLQueryItem(name: key, value: value)
      }

      finalQueryItems.append(contentsOf: queryItems)
    }

    urlComponents?.queryItems = finalQueryItems

    return urlComponents?.url
  }
}

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
