// Created by kai_chen on 5/4/21.

import Color
import Foundation
import Money
import SwiftUI
import UIKit

// MARK: - PriceHistory

public struct PriceHistory: Codable {
  // MARK: Lifecycle

  public init(date: Date, price: Money<USD>) {
    self.date = date
    self.price = price
  }

  // MARK: Public

  public let date: Date
  public let price: Money<USD>
}

// MARK: - Stock

public struct Stock: Codable {
  // MARK: Lifecycle

  public init(
    symbol: String,
    name: String,
    expectedPrice: Money<USD>,
    memo: String = "",
    currentQuote: StockCurrentQuote,
    expectedPriceHistory: [PriceHistory]
  ) {
    self.symbol = symbol
    self.name = name
    self.expectedPrice = expectedPrice
    self.memo = memo
    self.currentQuote = currentQuote
    self.expectedPriceHistory = expectedPriceHistory
  }

  // MARK: Public

  public let symbol: String
  public let name: String
  public let expectedPrice: Money<USD>
  public let memo: String
  public let currentQuote: StockCurrentQuote
  public let expectedPriceHistory: [PriceHistory]
}

// MARK: Equatable

extension Stock: Equatable {
  public static func == (lhs: Stock, rhs: Stock) -> Bool {
    lhs.symbol == rhs.symbol
  }
}

// MARK: Identifiable

extension Stock: Identifiable {
  public var id: String {
    symbol
  }
}

// MARK: Hashable

extension Stock: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(symbol)
  }
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
      expectedPriceHistory: []
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

  var priceColor: Color {
    isChangePercentNegative ? .stockRed : .stockGreen
  }

  var actionColor: Color {
    switch tradeAction {
      case .buy:
        return .stockGreen
      case .wait:
        return .stockRed
      case .almost:
        return .banana
    }
  }

  func with(currentQuote: StockCurrentQuote) -> Stock {
    Stock(
      symbol: symbol,
      name: name,
      expectedPrice: expectedPrice,
      memo: memo,
      currentQuote: currentQuote,
      expectedPriceHistory: expectedPriceHistory
    )
  }

  func with(memo: String) -> Stock {
    Stock(
      symbol: symbol,
      name: name,
      expectedPrice: expectedPrice,
      memo: memo,
      currentQuote: currentQuote,
      expectedPriceHistory: expectedPriceHistory
    )
  }
}
