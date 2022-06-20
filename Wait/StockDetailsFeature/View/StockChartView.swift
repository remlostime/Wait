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

  @State var currentX: CGFloat? = nil

  var body: some View {
    VStack {
      if let chartData = chartData {
        Chart(chartData.points) { point in
          LineMark(x: .value("timestamp", point.x), y: .value("price", point.y))

          if let currentX = currentX {
            RuleMark(x: .value("point", currentX))
              .foregroundStyle(.gray.opacity(0.1))
              .lineStyle(.init(lineWidth: 1.0))
          }
        }
        .chartXAxis(.hidden)
        .chartOverlay { proxy in
          GeometryReader.init { geoProxy in
            Rectangle().fill(.clear).contentShape(Rectangle())
              .gesture(DragGesture()
                .onChanged { value in
                  let x = value.location.x - geoProxy[proxy.plotAreaFrame].origin.x

                  currentX = proxy.value(atX: x)
                }
                .onEnded { _ in currentX = nil }
              )
          }
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
