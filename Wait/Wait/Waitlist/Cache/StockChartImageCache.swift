//
// Created by: kai_chen on 7/11/21.
// Copyright © 2021 Wait. All rights reserved.
//

import CacheService
import Foundation
import Logging
import Model

class StockChartImageCache {
  // MARK: Internal

  static let shared = StockChartImageCache()

  func getImage(symbol: String) -> PriceChartImage? {
    cache.value(forKey: symbol)
  }

  func saveImage(symbol: String, image: PriceChartImage) {
    cache.setValue(image, forKey: symbol)
  }

  // MARK: Private

  private let cache = Cache<String, PriceChartImage>()
}
