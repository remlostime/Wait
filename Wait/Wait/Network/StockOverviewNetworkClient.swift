//
// Created by: kai_chen on 6/6/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Alamofire
import Foundation
import Model
import Networking
import SwiftUI

final class StockOverviewNetworkClient: ObservableObject {
  // MARK: Internal

  @Published var stockOverview = StockOverview(
    name: "",
    description: "",
    PERatio: "",
    PBRatio: "",
    marketCap: "",
    dividendPerShare: ""
  )

  func fetchStockOverview(stock: Stock) {
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

          self.stockOverview = stockOverview
        case let .failure(error):
          logger.error("Failed to fetch stock quote: \(error.localizedDescription)")
      }
    }
  }

  // MARK: Private

  private func buildURL(stock: Stock) -> URL? {
    let params = [
      "symbol": stock.symbol,
      "function": "OVERVIEW",
    ]

    let url = NetworkingURLBuilder.buildURL(domain: .alphaVantage, api: "query", params: params)

    return url
  }
}
