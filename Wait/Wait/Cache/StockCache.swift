// Created by kai_chen on 5/8/21.

import Cache
import Foundation
import Model
import Logging

class StockCache {
  // MARK: Lifecycle

  private init() {}

  // MARK: Internal

  static let shared = StockCache()

  func getStocks() -> [Stock] {
    guard let stocks = try? storage?.object(forKey: key) else {
      return []
    }

    return stocks
  }

  func getStocks(completion: @escaping (([Stock]) -> Void)) {
    storage?.async.object(forKey: key) { result in
      switch result {
        case let .value(stocks):
          completion(stocks)
        case let .error(error):
          logger.error("Failed to fetch stocks: \(error.localizedDescription)")
      }
    }
  }

  func saveStocks(_ stocks: [Stock]) {
    storage?.async.setObject(stocks, forKey: key) { result in
      switch result {
        case .value:
          logger.verbose("Successfully store stocks")
        case let .error(error):
          logger.error("Failed to store stocks: \(error.localizedDescription)")
      }
    }
  }

  func saveStock(_ stock: Stock) {
    var stocks = getStocks()
    stocks.removeAll(stock)
    stocks.append(stock)

    saveStocks(stocks)
  }

  func removeStock(_ stock: Stock) {
    var stocks = getStocks()

    stocks.removeAll(stock)

    saveStocks(stocks)
  }

  // MARK: Private

  private let key = "stocks"

  private lazy var storage: Storage<String, [Stock]>? = {
//    let diskUrl = try? FileManager.default.url(
//      for: .documentDirectory,
//      in: .userDomainMask,
//      appropriateFor: nil,
//      create: true
//    )
    let diskUrl =  FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.chenkai.wait.contents")

    let diskConfig = DiskConfig(name: "stocks", directory: diskUrl)

    let memoryConfig = MemoryConfig()

    let storage = try? Storage<String, [Stock]>(
      diskConfig: diskConfig,
      memoryConfig: memoryConfig,
      transformer: TransformerFactory.forCodable(ofType: [Stock].self)
    )

    return storage
  }()
}
