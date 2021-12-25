//
// Created by: kai_chen on 8/8/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Combine
import Foundation
import Logging
import Model

class SearchStockDataSource: ObservableObject {
  // MARK: Internal

  @Published var searchStocks: [SearchStockResult] = []

  func searchStocks(for keyword: String) {
    guard !keyword.isEmpty else {
      searchStocks = []
      return
    }

    searchStockNetworkClient.searchStocks(for: keyword)
      .receive(on: DispatchQueue.main)
      .sink { _ in
        Logger.shared.verbose("Successfully get recommend stocks for :\(keyword)")
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

  // MARK: Private

  private let searchStockNetworkClient = SearchStockNetworkClient()
  private var subscriptions = [AnyCancellable]()
}
