//
// Created by: Kai Chen on 6/27/22.
// Copyright © 2021 Wait. All rights reserved.
//

import SwiftUI
import Charts
import Money


private struct ChartPoint: Identifiable {
  let index: Int
  let price: Double
  
  var id: Int {
    index
  }
}

struct ExpectedStockPriceChart: View {
  let priceHistory: [Money<USD>]
  
  private var chartPoints: [ChartPoint] {
    priceHistory.map { price in
      ChartPoint(index: priceHistory.firstIndex(of: price)!, price: price.amountDoubleValue)
    }
  }
  
  private var chartYScaleDomain: ClosedRange<Int> {
    let minClose = chartPoints.reduce(Double(Int.max)) { closePrice, point in
      min(point.price, closePrice)
    }

    let maxClose = chartPoints.reduce(Double(Int.min)) { closePrice, point in
      max(point.price, closePrice)
    }

    return Int(ceil(minClose)) ... Int(ceil(maxClose))
  }
  
  var body: some View {
    Chart(chartPoints) { point in
      LineMark(x: .value("timestamp", point.index), y: .value("price", point.price))
    }
    .chartXAxis(.hidden)
    .chartYScale(domain: chartYScaleDomain)
  }
}

struct ExpectedStockPriceChart_Previews: PreviewProvider {
  static var previews: some View {
    ExpectedStockPriceChart(priceHistory: [
      Money<USD>.init(1.0),
      Money<USD>.init(2.0)
    ])
  }
}
