//
// Created by: kai_chen on 8/14/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import Combine
import Model

class StockOverviewDataSource: ObservableObject {
  @Published var stockOverview = StockOverview.empty

  func fetchStockOverview(stock: Stock) {
    networkClient.fetchStockOverview(stock: stock)
      .sink { _ in
        logger.verbose("Successfully fetch stock overview: \(stock.symbol)")
      } receiveValue: { [weak self] stockOverview in
        self?.stockOverview = stockOverview
      }
      .store(in: &subscriptions)
  }

  private let networkClient = StockOverviewNetworkClient()
  private var subscriptions = [AnyCancellable]()
}
