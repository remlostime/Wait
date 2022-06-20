//
// Created by: Kai Chen on 6/19/22.
// Copyright © 2021 Wait. All rights reserved.
//

import SwiftUI
import StockCharts
import Charts

struct StockChartView: View {
  @StateObject var dataSource: PriceHistoryDataSource
  @State private var selectedTimeSection: TimeSection = .day
  
  private var chartData: ChartData? {
    allChartData[selectedTimeSection]
  }
  
  private var allChartData: [TimeSection: ChartData] {
    dataSource.chartData
  }
  
  var body: some View {
    return VStack {
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
}

struct StockChartView_Previews: PreviewProvider {
  static var previews: some View {
    StockChartView(dataSource: PriceHistoryDataSource(symbol: "fb"))
  }
}
