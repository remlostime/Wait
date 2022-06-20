//
// Created by: Kai Chen on 6/19/22.
// Copyright © 2021 Wait. All rights reserved.
//

import Charts
import StockCharts
import SwiftUI

// MARK: - StockChartView

struct StockChartView: View {
  // MARK: Internal

  @StateObject var dataSource: PriceHistoryDataSource

  var body: some View {
    VStack {
      if let chartData = chartData {
        Chart(chartData.points) { point in
          LineMark(x: .value("timestamp", point.x), y: .value("price", point.y))
        }
      } else {
        Chart {
          EmptyChartContent()
        }
      }

      Picker("StockChart", selection: $selectedTimeSection) {
        ForEach(allChartData.keys.sorted(by: { a, b in a.rawValue < b.rawValue })) { timeSection in
          Text(timeSection.timeSectionDescription)
            .tag(timeSection)
        }
      }
      .pickerStyle(SegmentedPickerStyle())
    }
    .onAppear {
      dataSource.fetchData(for: TimeSection.allCases)
    }
  }

  // MARK: Private

  @State private var selectedTimeSection: TimeSection = .day

  private var chartData: ChartData? {
    allChartData[selectedTimeSection]
  }

  private var allChartData: [TimeSection: ChartData] {
    dataSource.chartData
  }
}

// MARK: - StockChartView_Previews

struct StockChartView_Previews: PreviewProvider {
  static var previews: some View {
    StockChartView(dataSource: PriceHistoryDataSource(symbol: "fb"))
  }
}
