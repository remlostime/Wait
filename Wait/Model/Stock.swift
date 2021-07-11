// Created by kai_chen on 5/4/21.

import Color
import Foundation
import Money
import SwiftUI
import UIKit

// MARK: - Stock

public struct Stock: Codable {
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

  public var formattedChangePercent: String {
    let changePercentDouble = Double(changePercent) ?? 0.0
    let formattedChangePercent = String(format: "%.2f", changePercentDouble) + "%"
    return formattedChangePercent
  }

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

// MARK: Equatable

extension Stock: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.symbol == rhs.symbol
  }
}

// MARK: - TradeAction

public enum TradeAction: String, CaseIterable {
  case buy = "Buy"
  case wait = "Wait"
  case almost = "Almost"
}

public extension Stock {
  static var empty: Self {
    Stock(
      symbol: "",
      name: "",
      currentPrice: 0.0,
      expectedPrice: 0.0,
      changePercent: "",
      priceChartImage: nil
    )
  }

  var tradeAction: TradeAction {
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

  var comparedToCurrentPriceRate: String {
    String(format: "%.2f", currentPrice.amountDoubleValue / expectedPrice.amountDoubleValue)
  }

  var isChangePercentNegative: Bool {
    guard let first = changePercent.first else {
      return false
    }

    return first == "-"
  }

  var priceUIColor: UIColor {
    isChangePercentNegative ? .stockRed : .stockGreen
  }

  var priceColor: Color {
    Color(priceUIColor)
  }

  var actionUIColor: UIColor {
    switch tradeAction {
      case .buy:
        return .stockGreen
      case .wait:
        return .stockRed
      case .almost:
        return .banana
    }
  }

  var actionColor: Color {
    Color(actionUIColor)
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
