// Created by kai_chen on 5/17/21.

import Charts
import Color
import Foundation
import Model
import Money
import UIKit

final class PriceHistoryDataSource: ObservableObject, ChartViewDataSource {
  // MARK: Lifecycle

  init(symbol: String) {
    self.symbol = symbol
    chartCache = ChartCache<ChartModelType>(
      cacheName: "price-history",
      symbol: symbol
    )
    chartData = [:]
  }

  // MARK: Internal

  typealias ChartModelType = [TimeSection: [StockQuote]]

  @Published private(set) var chartData: [TimeSection: ChartData]
  weak var delegate: ChartViewDataSourceDelegate?

  var symbol: String

  var currentPrice: Money<USD> {
    guard let quote = models[.day]?.first else {
      return 0.0
    }

    return quote.close
  }

  func setDelegate(delegate: ChartViewDataSourceDelegate) {
    self.delegate = delegate
  }

  func fetchCurrentQuotes() {}

  func fetchData(for timeSections: [TimeSection]) {
    models = [:]

    chartCache.getChartData { [weak self] chartCacheData in
      guard let self = self, let chartCacheData = chartCacheData else {
        return
      }

      self.models = chartCacheData
      self.updateChartData()
    }

    let group = DispatchGroup()

    for timeSection in timeSections {
      group.enter()

      priceNetworkClient.fetchHistory(symbol: symbol, timeSection: timeSection) { [weak self] models in
        self?.models[timeSection] = models
        group.leave()
      }
    }

    group.notify(queue: .main) { [weak self] in
      guard let self = self else {
        return
      }
      self.updateChartData()
      self.chartCache.setChartData(self.models)
    }
  }

  // MARK: Private

  private let currentQuoteNetworkClient = StockQuoteNetworkClient()
  private let priceNetworkClient = PriceHistoryNetworkClient()
  private var models: ChartModelType = [:]
  private var priceHistories: [TimeSection: ChartData] = [:]
  private let chartCache: ChartCache<ChartModelType>

  private func buildChartData(quotes: [StockQuote]) -> ChartData {
    var entries: [ChartDataEntry] = []
    var index = 0
    for quote in quotes {
      guard let y = quote.close.amountDoubleValue else {
        continue
      }

      let data = ChartDataEntry(x: Double(index), y: y, data: quote)

      entries.append(data)

      index += 1
    }

    let chartDataSet = LineChartDataSet(entries: entries)
    chartDataSet.drawIconsEnabled = false
    chartDataSet.lineWidth = 2.0
    chartDataSet.drawCirclesEnabled = false
    chartDataSet.drawValuesEnabled = false
    chartDataSet.valueFont = .systemFont(ofSize: 9)
    chartDataSet.drawVerticalHighlightIndicatorEnabled = true
    chartDataSet.drawHorizontalHighlightIndicatorEnabled = false
    chartDataSet.highlightLineWidth = 1.0
    chartDataSet.highlightColor = .lightGray

    let chartColor: UIColor
    if
      let firstPrice = quotes.first?.close,
      let lastPrice = quotes.last?.close
    {
      chartColor = lastPrice >= firstPrice ? .stockGreen : .stockRed
    } else {
      chartColor = .stockGreen
    }

    chartDataSet.setColor(chartColor)
    chartDataSet.fillColor = chartColor

    let data = LineChartData(dataSet: chartDataSet)

    return data
  }

  private func updateChartData() {
    for (timeSection, quotes) in models {
      priceHistories[timeSection] = buildChartData(quotes: quotes)
    }

    chartData = priceHistories
    delegate?.dataDidUpdate(priceHistories)
  }
}
