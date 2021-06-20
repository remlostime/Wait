// Created by kai_chen on 5/4/21.

import Foundation
import Money
import UIKit

// MARK: - Stock

public struct Stock: Codable, Equatable {
  // MARK: Lifecycle

  public init(
    symbol: String,
    name: String,
    currentPrice: Money<USD>,
    expectedPrice: Money<USD>,
    changePercent: String,
    priceChartImage: PriceChartImage?
  ) {
    self.symbol = symbol
    self.name = name
    self.currentPrice = currentPrice
    self.expectedPrice = expectedPrice
    self.changePercent = changePercent
    self.priceChartImage = priceChartImage
  }

  // MARK: Public

  public let symbol: String
  public let name: String
  public let currentPrice: Money<USD>
  public let expectedPrice: Money<USD>
  public let changePercent: String
  public let priceChartImage: PriceChartImage?

  public func with(priceChartImage: PriceChartImage) -> Self {
    Self(
      symbol: symbol,
      name: name,
      currentPrice: currentPrice,
      expectedPrice: expectedPrice,
      changePercent: changePercent,
      priceChartImage: priceChartImage
    )
  }
}

public enum TradeAction: String, CaseIterable {
  case buy = "Buy"
  case wait = "Wait"
  case almost = "Almost"
}

extension Stock {
  public var tradeAction: TradeAction {
    let diffPercent = 0.05

    if currentPrice <= expectedPrice {
      return .buy
    } else {
      if currentPrice <= expectedPrice * (1 + diffPercent) {
        return .almost
      } else {
        return .wait
      }
    }
  }
}

// MARK: - PriceChartImage

public struct PriceChartImage: Codable, Equatable {
  // MARK: Lifecycle

  init(image: UIImage) {
    data = image.pngData()
  }

  // MARK: Public

  public var image: UIImage? {
    guard let data = data else {
      return nil
    }

    return UIImage(data: data)
  }

  // MARK: Private

  private let data: Data?
}
