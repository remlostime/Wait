//
// Created by: Kai Chen on 6/27/22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import SwiftUI
import Model
import Charts
import StockCharts

struct StockChartSnapshotView: View {
  
  let chartData: ChartData
  
  private var chartYScaleDomain: ClosedRange<Int> {
    let minClose = chartData.points.reduce(Double(Int.max)) { closePrice, point in
      min(point.quote.close.amountDoubleValue, closePrice)
    }

    let maxClose = chartData.points.reduce(Double(Int.min)) { closePrice, point in
      max(point.quote.close.amountDoubleValue, closePrice)
    }

    return Int(ceil(minClose)) ... Int(ceil(maxClose))
  }
  
  var body: some View {
    Chart(chartData.points) { point in
      LineMark(x: .value("timestamp", point.index), y: .value("price", point.quote.close.amountDoubleValue))
    }
    .chartXAxis(.hidden)
    .chartYAxis(.hidden)
    .chartYScale(domain: chartYScaleDomain)
  }
}
