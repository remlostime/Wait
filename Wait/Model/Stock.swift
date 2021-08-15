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
    currentQuote: StockCurrentQuote,
    category: StockCategory,
    lastUpdatedTime: Date
  ) {
    self.symbol = symbol
    self.name = name
    self.expectedPrice = expectedPrice
    self.memo = memo
    self.currentQuote = currentQuote
    self.category = category
    self.lastUpdatedTime = lastUpdatedTime
  }

  public init(from record: CKRecord) {
    symbol = (record["symbol"] as? String) ?? ""
    name = (record["name"] as? String) ?? ""
    let expectedPriceString = (record["expectedPrice"] as? String) ?? "0"
    expectedPrice = Money<USD>(stringLiteral: expectedPriceString)
    memo = (record["memo"] as? String) ?? ""

    if let categoryInt = record["category"] as? Int,
       let _category = StockCategory(rawValue: categoryInt)
    {
      category = _category
    } else {
      category = .research
    }

    lastUpdatedTime = (record["lastUpdatedTime"] as? Date) ?? Date()

    if let currentQuoteRecord = record["currentQuote"] as? CKRecord.Reference {
      currentQuote = .empty
      let id = currentQuoteRecord.recordID

      CloudNetworkClient.shared.fetch(recordID: id) { [weak self] result in
        switch result {
          case let .success(stockCurrentQuote):
            self?.currentQuote = stockCurrentQuote
          case let .failure(error):
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
  public let category: StockCategory
  public private(set) var currentQuote: StockCurrentQuote
  public let lastUpdatedTime: Date

  public func with(memo: String) -> Stock {
    Stock(
      symbol: symbol,
      name: name,
      expectedPrice: expectedPrice,
      memo: memo,
      currentQuote: currentQuote,
      category: category,
      lastUpdatedTime: lastUpdatedTime
    )
  }

  public func with(category: StockCategory) -> Stock {
    Stock(
      symbol: symbol,
      name: name,
      expectedPrice: expectedPrice,
      memo: memo,
      currentQuote: currentQuote,
      category: category,
      lastUpdatedTime: lastUpdatedTime
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

// MARK: Extension

public extension Stock {
  static var empty: Stock {
    Stock(
      symbol: "empty",
      name: "Empty",
      expectedPrice: 0.0,
      memo: "Empty",
      currentQuote: .empty,
      category: .waitlist,
      lastUpdatedTime: Date()
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
