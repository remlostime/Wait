//
// Created by: kai_chen on 8/14/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Combine
import Foundation
import Logging
import Model

class StockOverviewDataSource: ObservableObject {
  // MARK: Internal

  @Published var stockOverview = StockOverview.empty

  func fetchStockOverview(stock: Stock) {
    networkClient.fetchStockOverview(stock: stock)
      .receive(on: DispatchQueue.main)
      .sink { _ in
        Logger.shared.verbose("Successfully fetch stock overview: \(stock.symbol)")
      } receiveValue: { [weak self] stockOverview in
        self?.stockOverview = stockOverview
      }
      .store(in: &subscriptions)
  }

  // MARK: Private

  private let networkClient = StockOverviewNetworkClient()
  private var subscriptions = [AnyCancellable]()
}
