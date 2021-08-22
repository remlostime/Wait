//
// Created by: kai_chen on 7/11/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Cache
import Foundation
import Logging
import Model

class StockChartImageCache {
  // MARK: Lifecycle

  private init() {}

  // MARK: Internal

  static let shared = StockChartImageCache()

  func getImage(symbol: String) -> PriceChartImage? {
    try? storage?.object(forKey: symbol)
  }

  func saveImage(symbol: String, image: PriceChartImage) {
    storage?.async.setObject(image, forKey: symbol) { result in
      switch result {
        case .value:
          logger.verbose("Successfully store stock image: \(symbol)")
        case let .error(error):
          logger.error("Failed to store stock \(symbol) image: \(error.localizedDescription)")
      }
    }
  }

  // MARK: Private

  private let name = "stock-image"

  private lazy var storage: Storage<String, PriceChartImage>? = {
    let diskConfig = DiskConfig(name: name, expiry: .seconds(1000))

    let memoryConfig = MemoryConfig()

    let storage = try? Storage<String, PriceChartImage>(
      diskConfig: diskConfig,
      memoryConfig: memoryConfig,
      transformer: TransformerFactory.forCodable(ofType: PriceChartImage.self)
    )

    return storage
  }()
}
