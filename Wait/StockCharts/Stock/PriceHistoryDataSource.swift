// Created by kai_chen on 5/17/21.

import Color
import Foundation
import Model
import Money
import SwiftUI
import UIKit

public final class PriceHistoryDataSource: ObservableObject, ChartViewDataSource {
  // MARK: Lifecycle

  public init(symbol: String) {
    self.symbol = symbol
    chartCache = ChartCache<ChartModelType>(
      cacheName: "price-history",
      symbol: symbol
    )
    chartData = [:]
  }

  // MARK: Public

  @Published public private(set) var chartData: [TimeSection: ChartData]

  public weak var delegate: ChartViewDataSourceDelegate?

  public var currentPrice: Money<USD> {
    guard let quote = models[.day]?.last else {
      return 0.0
    }

    return quote.close
  }

  public func setDelegate(delegate: ChartViewDataSourceDelegate) {
    self.delegate = delegate
  }

  public func fetchData(for timeSections: [TimeSection]) {
    models = [:]

    if let chartData = chartCache.getChartData() {
      models = chartData
      updateChartData()
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

  // MARK: Internal

  typealias ChartModelType = [TimeSection: [StockQuote]]

  var symbol: String

  // MARK: Private

  private let priceNetworkClient = PriceHistoryNetworkClient()
  private var models: ChartModelType = [:]
  private var priceHistories: [TimeSection: ChartData] = [:]
  private let chartCache: ChartCache<ChartModelType>

  private func buildChartData(quotes: [StockQuote]) -> ChartData {
    let chartColor: Color
    if
      let firstPrice = quotes.first?.close,
      let lastPrice = quotes.last?.close
    {
      chartColor = lastPrice >= firstPrice ? .stockGreen : .stockRed
    } else {
      chartColor = .stockGreen
    }

    return ChartData(chartColor: chartColor, quotes: quotes)
  }

  private func updateChartData() {
    for (timeSection, quotes) in models {
      priceHistories[timeSection] = buildChartData(quotes: quotes)
    }

    DispatchQueue.main.async {
      self.chartData = self.priceHistories
      self.delegate?.dataDidUpdate(self.priceHistories)
    }
  }
}
