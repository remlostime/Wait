// Created by kai_chen on 5/8/21.

import Cache
import Foundation
import Model

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

  // MARK: Private

  private let key = "stocks"

  private lazy var storage: Storage<String, [Stock]>? = {
    let diskConfig = DiskConfig(name: "stocks")
    let memoryConfig = MemoryConfig()

    let storage = try? Storage<String, [Stock]>(
      diskConfig: diskConfig,
      memoryConfig: memoryConfig,
      transformer: TransformerFactory.forCodable(ofType: [Stock].self)
    )

    return storage
  }()
}
