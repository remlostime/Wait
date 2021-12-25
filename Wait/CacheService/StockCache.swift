// Created by kai_chen on 5/8/21.

import Cache
import Foundation
import Logging
import Model

public class StockCache {
  // MARK: Lifecycle

  private init() {}

  // MARK: Public

  public static let shared = StockCache()

  public func getStocks() -> [Stock] {
    guard let stocks = try? storage?.object(forKey: key) else {
      return []
    }

    return stocks
  }

  public func getStocks(completion: @escaping (([Stock]) -> Void)) {
    storage?.async.object(forKey: key) { result in
      switch result {
        case let .value(stocks):
          completion(stocks)
        case let .error(error):
          Logger.shared.error("Failed to fetch stocks: \(error.localizedDescription)")
      }
    }
  }

  public func saveStocks(_ stocks: [Stock]) {
    storage?.async.setObject(stocks, forKey: key) { result in
      switch result {
        case .value:
          Logger.shared.verbose("Successfully store stocks")
        case let .error(error):
          Logger.shared.error("Failed to store stocks: \(error.localizedDescription)")
      }
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

  private let key = "stocks"

  private lazy var storage: Storage<String, [Stock]>? = {
//    let diskUrl = try? FileManager.default.url(
//      for: .documentDirectory,
//      in: .userDomainMask,
//      appropriateFor: nil,
//      create: true
//    )
    let diskUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.chenkai.wait.contents")

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
