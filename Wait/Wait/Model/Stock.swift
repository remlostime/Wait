// Created by kai_chen on 5/4/21.

import Foundation
import Money
import UIKit

struct Stock: Codable, Equatable {
  let symbol: String
  let name: String
  let currentPrice: Money<USD>
  let expectedPrice: Money<USD>
  let changePercent: String
  let priceChartImage: PriceChartImage?

  func with(priceChartImage: PriceChartImage) -> Stock {
    Stock(
      symbol: symbol,
      name: name,
      currentPrice: currentPrice,
      expectedPrice: expectedPrice,
      changePercent: changePercent,
      priceChartImage: priceChartImage)
  }
}

struct PriceChartImage: Codable, Equatable {
  private let data: Data?

  var image: UIImage? {
    guard let data = data else {
      return nil
    }

    return UIImage(data: data)
  }

  init(image: UIImage) {
    data = image.pngData()
  }
}
