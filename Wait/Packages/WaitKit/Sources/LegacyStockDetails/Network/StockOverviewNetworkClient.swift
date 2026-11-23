//
// Created by: kai_chen on 6/6/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Combine
import Foundation
import Model

// MARK: - StockOverviewNetworkClient

protocol StockOverviewNetworkClient {
  func fetchStockOverview(stock: Stock) -> AnyPublisher<StockOverview, Error>
}

// MARK: - EmptyStockOverviewNetworkClient

/// Alpha Vantage's OVERVIEW endpoint is Premium-only, so the stats section shows the empty overview
/// until plan 04 serves fundamentals from the Wait backend.
final class EmptyStockOverviewNetworkClient: StockOverviewNetworkClient {
  func fetchStockOverview(stock: Stock) -> AnyPublisher<StockOverview, Error> {
    Just(StockOverview.empty)
      .setFailureType(to: Error.self)
      .eraseToAnyPublisher()
  }
}
