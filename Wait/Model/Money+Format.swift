// Created by kai_chen on 5/17/21.
// Copyright © 2021 Airbnb Inc. All rights reserved.

import Foundation
import Money
import SwifterSwift

public extension Money {
  var amountDoubleValue: Double {
    amount.string.double()!
  }

  var formattedCurrency: String {
    formattedCurrency(format: .full)
  }

  enum CurrencyFormat {
    case short
    case full
  }

  func formattedCurrency(format: CurrencyFormat = .short) -> String {
    let formatter = NumberFormatter()

    formatter.numberStyle = .currency
    formatter.currencyCode = currency.code
    formatter.maximumFractionDigits = currency.minorUnit

    switch format {
      case .full:
        return formatter.string(for: amount) ?? amount.string
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
          case 1_000...:
            value = amountDoubleValue / 1_000
            suffixSign = "K"
          default:
            value = amountDoubleValue
            suffixSign = ""
        }

        if let formattedString = formatter.string(from: NSNumber(value: value)) {
          return formattedString + suffixSign
        } else {
          return amount.string
        }
    }
  }
}
