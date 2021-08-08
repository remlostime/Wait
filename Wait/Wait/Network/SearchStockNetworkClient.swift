//
// Created by: kai_chen on 8/8/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import Combine
import Networking
import Model

struct SearchStockNetworkClient {
  private func buildStockSearchURL(keyword: String) -> URL? {
    let params = [
      "symbol": keyword,
    ]

    let url = NetworkingURLBuilder.buildURL(api: "symbol_search", params: params)

    return url
  }

  func searchStocks(for keyword: String) -> AnyPublisher<SearchStockResults, Error> {
    let url = buildStockSearchURL(keyword: keyword)!

    return URLSession.shared
      .dataTaskPublisher(for: url)
      .map(\.data)
      .decode(type: SearchStockResults.self, decoder: JSONDecoder())
      .eraseToAnyPublisher()
  }
}
