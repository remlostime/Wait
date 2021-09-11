//
// Created by: kai_chen on 9/11/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import Combine
import Model
import Logging

final class StockCurrentQuoteDataSource: ObservableObject {
  @Published var stocks: [Stock] = []

  private let networkClient = StockCurrentQuoteNetworkClient()

  private var subscriptions: Set<AnyCancellable> = []

  func fetchStock(_ stock: Stock) {
    networkClient.fetchDetails(stock: stock)
      .sink { result in
        switch result {
          case .finished:
            logger.verbose("Successfully fetch stock: \(stock.symbol)")
          case .failure(let error):
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
            case .failure(let error):
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

  private func saveStocks() {
    StockCache.shared.saveStocks(stocks)
  }
}
