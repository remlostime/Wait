//
// Created by: Kai Chen on 6/27/22.
// Copyright © 2021 Wait. All rights reserved.
//

import Charts
import Money
import SwiftUI
import Model

// MARK: - ChartPoint

private struct ChartPoint: Identifiable {
  let index: Int
  let priceHistory: PriceHistory

  var id: Int {
    index
  }
}

// MARK: - ExpectedStockPriceChart

struct ExpectedStockPriceChart: View {
  // MARK: Internal

  let priceHistory: [PriceHistory]

  var body: some View {
    Chart(chartPoints) { point in
      LineMark(x: .value("timestamp", point.index), y: .value("price", point.priceHistory.price.amountDoubleValue))
    }
    .chartXAxis(.hidden)
    .chartYScale(domain: chartYScaleDomain)
  }

  // MARK: Private

  private var chartPoints: [ChartPoint] {
    var chartPoints = [ChartPoint]()
    for (index, val) in priceHistory.enumerated() {
      chartPoints.append(ChartPoint(index: index, priceHistory: val))
    }

    return chartPoints
  }

  private var chartYScaleDomain: ClosedRange<Int> {
    let minClose = chartPoints.reduce(Double(Int.max)) { closePrice, point in
      min(point.priceHistory.price.amountDoubleValue, closePrice)
    }

    let maxClose = chartPoints.reduce(Double(Int.min)) { closePrice, point in
      max(point.priceHistory.price.amountDoubleValue, closePrice)
    }

    return Int(ceil(minClose)) ... Int(ceil(maxClose))
  }
}

// MARK: - ExpectedStockPriceChart_Previews

struct ExpectedStockPriceChart_Previews: PreviewProvider {
  static var previews: some View {
    ExpectedStockPriceChart(priceHistory: [
      PriceHistory(date: Date(), price: Money<USD>.init(1.0)),
      PriceHistory(date: Date(), price: Money<USD>.init(2.0))
    ])
  }
}
