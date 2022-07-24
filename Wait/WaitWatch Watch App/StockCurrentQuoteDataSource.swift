//
// Created by: kai_chen on 9/11/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Combine
import Foundation
import SwiftUI

final class StockCurrentQuoteDataSource: ObservableObject {
  // MARK: Internal

  @Published var stocks: [Stock] = []

  func moveStock(fromOffset source: IndexSet, toOffset destination: Int) {
    stocks.move(fromOffsets: source, toOffset: destination)
    saveStocks()
  }

  func removeStock(_ stock: Stock) {
    stocks.removeAll(where: {
      $0 == stock
    })
  }

  func fetchStock(_ stock: Stock) {
    networkClient.fetchDetails(stock: stock)
      .sink { _ in
      } receiveValue: { stockQuote in
        DispatchQueue.main.async {
          let newStock = stock.with(currentQuote: stockQuote)
          self.stocks.append(newStock)
          self.saveStocks()
        }
      }
      .store(in: &subscriptions)
  }

  func fetchStocks() {
    let stocks = [Stock(symbol: "BABA", name: "", expectedPrice: .init(100), currentQuote: .init(symbol: "baba", name: "BABA", open: .init(100), high: .init(100), low: .init(100), close: .init(100), volume: "2343", datetime: .now, percentChange: "21"), expectedPriceHistory: [])]

    self.stocks = stocks

    networkClient.fetchDetails(stocks: stocks)
      .sink { _ in
      } receiveValue: { stockQuoteBatch in
        let newStocks: [Stock] = stocks.map {
          if let quote = stockQuoteBatch.quotes[$0.symbol] {
            return $0.with(currentQuote: quote)
          } else {
            return $0
          }
        }

        DispatchQueue.main.async {
          self.stocks = newStocks
          self.saveStocks()
        }
      }
      .store(in: &subscriptions)
  }

  // MARK: Private

  private let networkClient = StockCurrentQuoteNetworkClient()

  private var subscriptions: Set<AnyCancellable> = []

  private func saveStocks() {}
}
