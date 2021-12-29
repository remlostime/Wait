//
// Created by: kai_chen on 12/29/21.
// Copyright © 2021 Wait. All rights reserved.
//

import XCTest
import Model
import Combine
@testable import StockDetailsFeature

class MockStockOverviewNetworkClient: StockOverviewNetworkClient {

  private let stockOverview: StockOverview

  init(stockOverview: StockOverview) {
    self.stockOverview = stockOverview
  }

  func fetchStockOverview(stock: Stock) -> AnyPublisher<StockOverview, Error> {
    Result.Publisher(.success(stockOverview))
      .eraseToAnyPublisher()
  }
}

class StockOverviewNetworkClientTests: XCTestCase {

  private var cancellable: AnyCancellable?

  func testFetchStockOverview() {
    let stockOverview = StockOverview.empty

    let dataSource = StockOverviewDataSource(networkClient: MockStockOverviewNetworkClient(stockOverview: stockOverview))

    dataSource.fetchStockOverview(stock: .empty)

    cancellable = dataSource.$stockOverview.sink { newStockOverview in
      XCTAssertEqual(newStockOverview, stockOverview)
    }
  }
}
