//
// Created by: kai_chen on 7/11/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import Logging
import Model
import CacheService

class StockChartImageCache {
  // MARK: Public
  
  static let shared = StockChartImageCache()
  
  private let cache = Cache<String, PriceChartImage>()
  
  func getImage(symbol: String) -> PriceChartImage? {
    cache.value(forKey: symbol)
  }
  
  func saveImage(symbol: String, image: PriceChartImage) {
    cache.setValue(image, forKey: symbol)
  }
}
