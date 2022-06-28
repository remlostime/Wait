//
// Created by: Kai Chen on 6/19/22.
// Copyright © 2021 Wait. All rights reserved.
//

import Charts
import Size
import StockCharts
import SwiftUI

// MARK: - StockChartView

struct StockChartView: View {
  // MARK: Internal

  @StateObject var dataSource: PriceHistoryDataSource

  var body: some View {
    VStack(spacing: Size.verticalPadding24) {
      if let chartData = chartData {
        VStack(alignment: .leading, spacing: Size.verticalPadding24) {
          Text(currentPrice)
            .font(.title2)
            .padding(.leading, Size.horizontalPadding16)

          Chart(chartData.points) { point in
            LineMark(x: .value("timestamp", point.index), y: .value("price", point.quote.close.amountDoubleValue))

            if let currentIndex = currentIndex {
              RuleMark(x: .value("point", currentIndex))
                .foregroundStyle(.gray.opacity(0.1))
                .lineStyle(.init(lineWidth: 1.0))
                .annotation(position: .top) {
                  Text("\(timestamp)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                }
            }
          }
          .chartYScale(domain: chartYScaleDomain)
          .chartXAxis(.hidden)
          .chartOverlay { proxy in
            GeometryReader.init { geoProxy in
              Rectangle().fill(.clear).contentShape(Rectangle())
                .gesture(DragGesture()
                  .onChanged { value in
                    let x = value.location.x - geoProxy[proxy.plotAreaFrame].origin.x

                    currentIndex = proxy.value(atX: x)

                    if let currentIndex = currentIndex {
                      self.currentIndex = min(chartData.points.count - 1, currentIndex)
                    }
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

  @State private var currentIndex: Int? = nil

  @State private var selectedTimeSection: TimeSection = .day

  private var timestamp: String {
    guard let currentIndex = currentIndex, let chartData = chartData else {
      return ""
    }

    let date: Date.FormatStyle.DateStyle
    let time: Date.FormatStyle.TimeStyle

    switch selectedTimeSection {
      case .day:
        date = .omitted
        time = .shortened
      case .week:
        date = .abbreviated
        time = .shortened
      case .month:
        date = .abbreviated
        time = .omitted
      case .year:
        date = .abbreviated
        time = .omitted
      case .all:
        date = .abbreviated
        time = .omitted
    }

    return chartData.points[currentIndex].quote.date.formatted(date: date, time: time)
  }

  private var chartYScaleDomain: ClosedRange<Int> {
    guard let chartData = chartData else {
      return 0 ... 100
    }

    let minClose = chartData.points.reduce(Double(Int.max)) { closePrice, point in
      min(point.quote.close.amountDoubleValue, closePrice)
    }

    let maxClose = chartData.points.reduce(Double(Int.min)) { closePrice, point in
      max(point.quote.close.amountDoubleValue, closePrice)
    }

    return Int(floor(minClose)) ... Int(ceil(maxClose))
  }

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
