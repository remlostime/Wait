// Created by kai_chen on 5/17/21.
// Copyright © 2021 Airbnb Inc. All rights reserved.

import Foundation
import Money

public extension Money {
  enum CurrencyFormat {
    case short
    case full
  }

  var amountDoubleValue: Double {
    NSDecimalNumber(decimal: amount).doubleValue
  }

  var formattedCurrency: String {
    formattedCurrency(format: .full)
  }

  func formattedCurrency(format: CurrencyFormat = .short) -> String {
    let formatter = NumberFormatter()

    formatter.numberStyle = .currency
    formatter.currencyCode = currency.code
    formatter.maximumFractionDigits = currency.minorUnit

    switch format {
      case .full:
        return formatter.string(for: amount) ?? String(describing: amount)
      case .short:
        let value: Double
        let suffixSign: String

        switch amountDoubleValue {
          case 1_000_000_000...:
            value = amountDoubleValue / 1_000_000_000
            suffixSign = "B"
          case 1_000_000...:
            value = amountDoubleValue / 1_000_000
            suffixSign = "M"
          case 1000...:
            value = amountDoubleValue / 1000
            suffixSign = "K"
          default:
            value = amountDoubleValue
            suffixSign = ""
        }

        if let formattedString = formatter.string(from: NSNumber(value: value)) {
          return formattedString + suffixSign
        } else {
          return String(describing: amount)
        }
    }
  }
}
