//
// Created by: kai_chen on 6/6/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Alamofire
import Combine
import Foundation
import Model
import Networking
import SwiftUI

final class StockOverviewNetworkClient {
  // MARK: Internal

  func fetchStockOverview(stock: Stock) -> AnyPublisher<StockOverview, Error> {
    let url = buildURL(stock: stock)!

    return URLSession.shared
      .dataTaskPublisher(for: url)
      .map(\.data)
      .decode(type: StockOverview.self, decoder: Self.decoder)
      .eraseToAnyPublisher()
  }

  // MARK: Private

  private static let decoder = JSONDecoder()

  private func buildURL(stock: Stock) -> URL? {
    let params = [
      "symbol": stock.symbol,
      "function": "OVERVIEW",
    ]

    let url = NetworkingURLBuilder.buildURL(domain: .alphaVantage, api: "query", params: params)

    return url
  }
}
