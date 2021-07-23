// Created by kai_chen on 5/4/21.

import CloudKit
import Color
import Foundation
import Money
import SwiftUI
import UIKit

// MARK: - Stock

public class Stock: Codable {
  // MARK: Lifecycle

  public init(
    symbol: String,
    name: String,
    expectedPrice: Money<USD>,
    memo: String = "",
    currentQuote: StockCurrentQuote
  ) {
    self.symbol = symbol
    self.name = name
    self.expectedPrice = expectedPrice
    self.memo = memo
    self.currentQuote = currentQuote
  }

  public init(from record: CKRecord) {
    symbol = (record["symbol"] as? String) ?? ""
    name = (record["name"] as? String) ?? ""
    let expectedPriceString = (record["expectedPrice"] as? String) ?? "0"
    expectedPrice = Money<USD>(stringLiteral: expectedPriceString)
    memo = (record["memo"] as? String) ?? ""
    if let currentQuoteRecord = record["currentQuote"] as? CKRecord.Reference {
      currentQuote = .empty
      let id = currentQuoteRecord.recordID

      StockCurrentQuote.fetch(recordID: id) { [weak self] result in
        switch result {
          case .success(let stockCurrentQuote):
            self?.currentQuote = stockCurrentQuote
          case .failure(let error):
            print("error to fetch stock current quote: \(error.localizedDescription)")
        }
      }
    } else {
      currentQuote = .empty
    }
  }

  // MARK: Public

  public let symbol: String
  public let name: String
  public let expectedPrice: Money<USD>
  public let memo: String
  public var currentQuote: StockCurrentQuote

  public var currentPrice: Money<USD> {
    currentQuote.close
  }

  public var changePercent: String {
    currentQuote.percentChange
  }

  public var formattedChangePercent: String {
    let changePercentDouble = Double(changePercent) ?? 0.0
    let formattedChangePercent = String(format: "%.2f", changePercentDouble) + "%"
    return formattedChangePercent
  }

  public func with(memo: String) -> Stock {
    Stock(
      symbol: symbol,
      name: name,
      expectedPrice: expectedPrice,
      memo: memo,
      currentQuote: currentQuote
    )
  }
}

// MARK: Equatable

extension Stock: Equatable {
  public static func == (lhs: Stock, rhs: Stock) -> Bool {
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
  static var empty: Stock {
    Stock(
      symbol: "empty",
      name: "Empty",
      expectedPrice: 0.0,
      memo: "Empty",
      currentQuote: .empty
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

  public init(image: UIImage) {
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
