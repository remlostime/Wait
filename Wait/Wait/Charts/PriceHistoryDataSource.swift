// Created by kai_chen on 5/17/21.

import Charts
import Foundation
import Money
import UIKit

final class PriceHistoryDataSource: ChartViewDataSource {
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

  var chartData: [TimeSection: ChartData]
  weak var delegate: ChartViewDataSourceDelegate?

  var currentPrice: Money<USD> {
    guard let quote = models[.day]?.first else {
      return 0.0
    }

    return quote.price
  }

  func setDelegate(delegate: ChartViewDataSourceDelegate) {
    self.delegate = delegate
  }

  // MARK: Private

  private let symbol: String
  private let currentQuoteNetworkClient = StockQuoteNetworkClient()
  private let priceNetworkClient = PriceHistoryNetworkClient()
  private var models: ChartModelType = [:]
  private var priceHistories: [TimeSection: ChartData] = [:]
  private let chartCache: ChartCache<ChartModelType>

  func fetchCurrentQuotes() {
  }

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

//      priceNetworkClient.fetchHistory(symbol: symbol, timeSection: timeSection) { [weak self] models in
//        self?.models[timeSection] = models
//        group.leave()
//      }
    }

    group.notify(queue: .main) { [weak self] in
      guard let self = self else {
        return
      }
      self.updateChartData()
      self.chartCache.setChartData(self.models)
    }
  }

  private func buildChartData(quotes: [StockQuote]) -> ChartData {
    let entries = quotes.compactMap { quote -> ChartDataEntry? in
      if let y = quote.price.amountDoubleValue {
        return ChartDataEntry(x: quote.date.timeIntervalSince1970, y: y)
      } else {
        return nil
      }
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
      let firstPrice = quotes.first?.price,
      let lastPrice = quotes.last?.price
    {
      chartColor = lastPrice >= firstPrice ? .green : .red
    } else {
      chartColor = .green
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

    delegate?.dataDidUpdate(priceHistories)
  }
}
