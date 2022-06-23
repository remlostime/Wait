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

  @State var currentIndex: Int? = nil

  var body: some View {
    VStack {
      if let chartData = chartData {
        VStack(alignment: .leading) {
          Text(currentPrice)
            .font(.title2)

          // TODO: - For different chart show different start and end price chart
          Chart(chartData.points) { point in
            LineMark(x: .value("timestamp", point.index), y: .value("price", point.quote.close.amountDoubleValue))

            if let currentIndex = currentIndex {
              RuleMark(x: .value("point", currentIndex))
                .foregroundStyle(.gray.opacity(0.1))
                .lineStyle(.init(lineWidth: 1.0))
                .annotation(position: .top) {
                  // TODO: - Map `currentX` to chartData.points and show the currentX(date) value
                  Text("\(chartData.points[currentIndex].quote.date.formatted())")
                    .font(.headline)
                    .foregroundColor(.gray)
                }
            }
          }
          .chartXAxis(.hidden)
          .chartOverlay { proxy in
            GeometryReader.init { geoProxy in
              Rectangle().fill(.clear).contentShape(Rectangle())
                .gesture(DragGesture()
                  .onChanged { value in
                    let x = value.location.x - geoProxy[proxy.plotAreaFrame].origin.x

                    currentIndex = proxy.value(atX: x)
                  }
                  .onEnded { _ in currentIndex = nil }
                )
            }
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

  private var currentPrice: String {
    guard
      let currentIndex = currentIndex,
      let currentPrice = chartData?.points[currentIndex].quote.close
    else {
      return chartData?.points.last?.quote.close.amountDoubleValue.formatted() ?? "$0"
    }

    return currentPrice.amountDoubleValue.formatted()
  }

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
