//
// Created by: kai_chen on 6/6/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import Alamofire

final class StockOverviewNetworkClient {
  func fetchStockDetails(stock: Stock, completion: @escaping ((StockOverview) -> Void)) {
    guard let url = buildURL(stock: stock) else {
      return
    }

    AF.request(url).validate().responseData { response in
      switch response.result {
        case let .success(data):
          let decoder = JSONDecoder()

          guard
            let stockOverview = try? decoder.decode(StockOverview.self, from: data)
          else {
            logger.error("Failed to decode stock quote")
            return
          }

          completion(stockOverview)
        case let .failure(error):
          logger.error("Failed to fetch stock quote: \(error.localizedDescription)")
      }
    }
  }

  private func buildURL(stock: Stock) -> URL? {
    let params = [
      "symbol": stock.symbol,
      "function": "OVERVIEW"
    ]

    let url = NetworkingURLBuilder.buildURL(domain: .alphaVantage, api: "query", params: params)

    return url
  }
}

