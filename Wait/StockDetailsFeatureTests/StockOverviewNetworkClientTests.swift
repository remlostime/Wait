//
// Created by: kai_chen on 12/29/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Combine
import Model
import XCTest
@testable import StockDetailsFeature

// MARK: - MockStockOverviewNetworkClient

class MockStockOverviewNetworkClient: StockOverviewNetworkClient {
  // MARK: Lifecycle

  init(stockOverview: StockOverview) {
    self.stockOverview = stockOverview
  }

  // MARK: Internal

  func fetchStockOverview(stock: Stock) -> AnyPublisher<StockOverview, Error> {
    Result.Publisher(.success(stockOverview))
      .eraseToAnyPublisher()
  }

  // MARK: Private

  private let stockOverview: StockOverview
}

// MARK: - StockOverviewNetworkClientTests

class StockOverviewNetworkClientTests: XCTestCase {
  // MARK: Internal

  func testFetchStockOverview() {
    let stockOverview = StockOverview.empty

    let dataSource = StockOverviewDataSource(networkClient: MockStockOverviewNetworkClient(stockOverview: stockOverview))

    dataSource.fetchStockOverview(stock: .empty)

    cancellable = dataSource.$stockOverview.sink { newStockOverview in
      XCTAssertEqual(newStockOverview, stockOverview)
    }
  }

  // MARK: Private

  private var cancellable: AnyCancellable?
}
