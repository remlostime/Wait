// Created by kai_chen on 5/17/21.
// Copyright © 2021 Airbnb Inc. All rights reserved.

import Foundation
import Money
import SwifterSwift

extension Money {
  var amountDoubleValue: Double {
    amount.string.double()!
  }

  var formattedCurrency: String {
    let formatter = NumberFormatter()

    formatter.numberStyle = .currency
    formatter.currencyCode = currency.code
    formatter.maximumFractionDigits = currency.minorUnit

    return formatter.string(for: amount) ?? amount.string
  }
}
