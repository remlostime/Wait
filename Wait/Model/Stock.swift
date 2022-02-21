// Created by kai_chen on 5/4/21.

import Color
import Foundation
import Money
import SwiftUI
import UIKit

// MARK: - Stock

public struct Stock: Codable, Equatable {
  // MARK: Lifecycle

  public init(
    symbol: String,
    name: String,
    expectedPrice: Money<USD>,
    memo: String = "",
    currentQuote: StockCurrentQuote,
    updatedHistory: [UpdatedHistory]
  ) {
    self.symbol = symbol
    self.name = name
    self.expectedPrice = expectedPrice
    self.memo = memo
    self.currentQuote = currentQuote
    self.updatedHistory = updatedHistory
  }

  // MARK: Public

  public let symbol: String
  public let name: String
  public let expectedPrice: Money<USD>
  public var memo: String
  public private(set) var currentQuote: StockCurrentQuote
  public let updatedHistory: [UpdatedHistory]

  public static func == (lhs: Stock, rhs: Stock) -> Bool {
    lhs.symbol == rhs.symbol
  }

  public func with(currentQuote: StockCurrentQuote) -> Stock {
    Stock(
      symbol: symbol,
      name: name,
      expectedPrice: expectedPrice,
      memo: memo,
      currentQuote: currentQuote,
      updatedHistory: updatedHistory
    )
  }

  public func with(memo: String) -> Stock {
    Stock(
      symbol: symbol,
      name: name,
      expectedPrice: expectedPrice,
      memo: memo,
      currentQuote: currentQuote,
      updatedHistory: updatedHistory
    )
  }
}

// MARK: - TradeAction

public enum TradeAction: String, CaseIterable {
  case buy = "Buy"
  case wait = "Wait"
  case almost = "Almost"
}

// MARK: Extension

public extension Stock {
  static var empty: Stock {
    Stock(
      symbol: "Empty",
      name: "Empty",
      expectedPrice: 0.0,
      memo: "Empty",
      currentQuote: .empty,
      updatedHistory: []
    )
  }

  var currentPrice: Money<USD> {
    currentQuote.close
  }

  var changePercent: String {
    currentQuote.percentChange
  }

  var formattedChangePercent: String {
    let changePercentDouble = Double(changePercent) ?? 0.0
    let formattedChangePercent = String(format: "%.2f", changePercentDouble) + "%"
    return formattedChangePercent
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
