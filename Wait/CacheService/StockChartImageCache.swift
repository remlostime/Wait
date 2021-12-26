//
// Created by: kai_chen on 7/11/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Cache
import Foundation
import Logging
import Model

public class StockChartImageCache {
  // MARK: Lifecycle

  private init() {}

  // MARK: Public

  public static let shared = StockChartImageCache()

  public func getImage(symbol: String) -> PriceChartImage? {
    try? storage?.object(forKey: symbol)
  }

  public func saveImage(symbol: String, image: PriceChartImage) {
    storage?.async.setObject(image, forKey: symbol) { result in
      switch result {
        case .value:
          Logger.shared.verbose("Successfully store stock image: \(symbol)")
        case let .error(error):
          Logger.shared.error("Failed to store stock \(symbol) image: \(error.localizedDescription)")
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
