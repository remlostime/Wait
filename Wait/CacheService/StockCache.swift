// Created by kai_chen on 5/8/21.

import Foundation
import Logging
import Model

public class StockCache {
  // MARK: Lifecycle

  private init() {
    storage = Storage<[Stock]>(name: key)
  }

  // MARK: Public

  public static let shared = StockCache()

  public func getStocks() -> [Stock] {
    if stocks.isEmpty {
      getStocksFromDisk()
    }

    return stocks
  }

  public func saveStocks(_ stocks: [Stock]) {
    self.stocks = stocks

    do {
      try storage.saveValue(stocks)
    } catch {
      Logger.shared.error("Failed to encode stocks and save it. Error: \(error.localizedDescription)")
    }
  }

  public func saveStock(_ stock: Stock) {
    var stocks = getStocks()
    stocks.removeAll {
      stock.symbol == $0.symbol
    }
    stocks.append(stock)

    saveStocks(stocks)
  }

  public func removeStock(_ stock: Stock) {
    var stocks = getStocks()

    stocks.removeAll {
      stock.symbol == $0.symbol
    }

    saveStocks(stocks)
  }

  // MARK: Private

  private var stocks: [Stock] = []
  private let storage: Storage<[Stock]>

  private let key = "stocks"

  private let decoder = JSONDecoder()
  private let encoder = JSONEncoder()

  private let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "stocks")

  private func getStocksFromDisk() {
    do {
      stocks = try storage.value()
    } catch {
      Logger.shared.error("Failed to encode stocks and save it. Error: \(error.localizedDescription)")
    }
  }
}
