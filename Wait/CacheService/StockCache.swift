// Created by kai_chen on 5/8/21.

import Foundation
import Logging
import Model

public class StockCache {
  
  private var stocks: [Stock] = []
  
  private let key = "stocks"
  
  private let decoder = JSONDecoder()
  private let encoder = JSONEncoder()
  
  private let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "stocks")

  
  // MARK: Lifecycle

  private init() {}

  // MARK: Public

  public static let shared = StockCache()
  
  private func getStocksFromDisk() {
    do {
      let data = try Data(contentsOf: path)
      self.stocks = try decoder.decode([Stock].self, from: data)
    } catch {
      Logger.shared.error("Failed to encode stocks and save it. Error: \(error.localizedDescription)")
    }
  }

  public func getStocks() -> [Stock] {
    if stocks.isEmpty {
      getStocksFromDisk()
    }
    
    return stocks
  }

  public func saveStocks(_ stocks: [Stock]) {
    self.stocks = stocks
    
    do {
      let data = try encoder.encode(stocks)
      try data.write(to: path)
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
}
