//
// Created by: Kai Chen on 6/19/22.
// Copyright © 2021 Wait. All rights reserved.
//

import Charts
import Foundation
import Money

struct ValuationData: Identifiable {
  enum `Type`: String, Plottable {
    case expected
    case current
  }

  let price: Money<USD>
  let type: Type

  var id: Type {
    type
  }
}
