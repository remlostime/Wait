//
// Created by: kai_chen on 8/8/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Combine
import Foundation
import Model
import Networking

struct SearchStockNetworkClient {
  // MARK: Internal

  func searchStocks(for keyword: String) -> AnyPublisher<SearchStockResults, Error> {
    let url = buildStockSearchURL(keyword: keyword)!

    return URLSession.shared
      .dataTaskPublisher(for: url)
      .map(\.data)
      .decode(type: SearchStockResults.self, decoder: JSONDecoder())
      .eraseToAnyPublisher()
  }

  // MARK: Private

  private func buildStockSearchURL(keyword: String) -> URL? {
    let params = [
      "symbol": keyword,
    ]

    let url = NetworkingURLBuilder.buildURL(api: "symbol_search", params: params)

    return url
  }
}
