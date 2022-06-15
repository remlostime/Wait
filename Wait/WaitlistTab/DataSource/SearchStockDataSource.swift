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
        let stocks = $0.data
        
        DispatchQueue.main.async {
          self?.searchStocks = stocks.filter {
            Exchange(rawValue: $0.exchange) == nil ? false : true
          }
        }
      }
      .store(in: &subscriptions)
  }

  // MARK: Private

  private let searchStockNetworkClient = SearchStockNetworkClient()
  private var subscriptions = [AnyCancellable]()
}
