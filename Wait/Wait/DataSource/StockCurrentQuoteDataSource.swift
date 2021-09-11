//
// Created by: kai_chen on 9/11/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Combine
import Foundation
import Logging
import Model

final class StockCurrentQuoteDataSource: ObservableObject {
  // MARK: Internal

  @Published var stocks: [Stock] = []

  func fetchStock(_ stock: Stock) {
    networkClient.fetchDetails(stock: stock)
      .sink { result in
        switch result {
          case .finished:
            logger.verbose("Successfully fetch stock: \(stock.symbol)")
          case let .failure(error):
            logger.error("Failed to fetch stock: \(stock.symbol). Error: \(error.localizedDescription)")
        }
      } receiveValue: { stockQuote in
        let newStock = stock.with(currentQuote: stockQuote)
        self.stocks.append(newStock)
        self.saveStocks()
      }
      .store(in: &subscriptions)
  }

  func fetchStocks() {
    StockCache.shared.getStocks { stocks in
      DispatchQueue.main.async {
        self.stocks = stocks
      }

      self.networkClient.fetchDetails(stocks: stocks)
        .sink { result in
          let symbols = stocks.map { $0.symbol }
          switch result {
            case .finished:
              logger.verbose("Successfully fetch stocks: \(symbols)")
            case let .failure(error):
              logger.error("Failed to fetch stock: \(symbols). Error: \(error.localizedDescription)")
          }
        } receiveValue: { stockQuoteBatch in
          let newStocks: [Stock] = stocks.map {
            if let quote = stockQuoteBatch.quotes[$0.symbol] {
              return $0.with(currentQuote: quote)
            } else {
              return $0
            }
          }

          DispatchQueue.main.async {
            logger.verbose("Update all stocks quote")
            self.stocks = newStocks
            self.saveStocks()
          }
        }
        .store(in: &self.subscriptions)
    }
  }

  // MARK: Private

  private let networkClient = StockCurrentQuoteNetworkClient()

  private var subscriptions: Set<AnyCancellable> = []

  private func saveStocks() {
    StockCache.shared.saveStocks(stocks)
  }
}