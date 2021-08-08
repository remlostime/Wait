//
// Created by: kai_chen on 8/8/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import Combine
import Model

class SearchStockDataSource: ObservableObject {
  @Published var searchStocks: [SearchStockResult] = []

  private let searchStockNetworkClient = SearchStockNetworkClient()
  private var subscriptions = [AnyCancellable]()

  func searchStocks(for keyword: String) {
    searchStockNetworkClient.searchStocks(for: keyword)
      .sink { _ in
        logger.verbose("Successfully get recommend stocks for :\(keyword)")
      } receiveValue: { [weak self] in
        let acceptedExchange: Set<Exchange> = Set(Exchange.allCases)
        let stocks = $0.data
        self?.searchStocks = stocks.filter {
          guard let exchangeType = Exchange(rawValue: $0.exchange) else {
            return false
          }

          return acceptedExchange.contains(exchangeType)
        }
      }
      .store(in: &subscriptions)
  }
}
