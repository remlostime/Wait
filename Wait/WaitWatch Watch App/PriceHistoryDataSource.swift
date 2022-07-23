//
// Created by: Kai Chen on 7/23/22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import Money
import SwiftUI
import UIKit

// MARK: - StockQuote

public struct StockQuote: Codable {
  // MARK: Public

  public let open: Money<USD>
  public let high: Money<USD>
  public let low: Money<USD>
  public let close: Money<USD>
  public let date: Date

  // MARK: Internal

  enum CodingKeys: String, CodingKey {
    case open
    case high
    case low
    case close
    case date = "datetime"
  }
}

// MARK: Identifiable

extension StockQuote: Identifiable {
  public var id: Date {
    date
  }
}

// MARK: - ChartPoint

public struct ChartPoint {
  public let index: Int
  public let quote: StockQuote
}

// MARK: - ChartData

struct ChartData {
  // MARK: Lifecycle

  public init(chartColor: Color, quotes: [StockQuote]) {
    self.chartColor = chartColor

    var index = 0
    var points: [ChartPoint] = []
    for quote in quotes {
      points.append(ChartPoint(index: index, quote: quote))
      index += 1
    }
    self.points = points
  }

  // MARK: Public

  public let chartColor: Color
  public let points: [ChartPoint]
}

// MARK: - PriceHistoryDataSource

final class PriceHistoryDataSource: ObservableObject {
  // MARK: Lifecycle

  public init(symbol: String) {
    self.symbol = symbol
    chartData = [:]
  }

  // MARK: Public

  @Published public private(set) var chartData: [TimeSection: ChartData]

  public var currentPrice: Money<USD> {
    guard let quote = models[.day]?.last else {
      return 0.0
    }

    return quote.close
  }

  public func fetchData(for timeSections: [TimeSection]) {
    models = [:]

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
    }
  }

  // MARK: Internal

  typealias ChartModelType = [TimeSection: [StockQuote]]

  var symbol: String

  // MARK: Private

  private let priceNetworkClient = PriceHistoryNetworkClient()
  private var models: ChartModelType = [:]
  private var priceHistories: [TimeSection: ChartData] = [:]

  private func buildChartData(quotes: [StockQuote]) -> ChartData {
    let chartColor: Color
    if
      let firstPrice = quotes.first?.close,
      let lastPrice = quotes.last?.close
    {
      chartColor = lastPrice >= firstPrice ? .green : .red
    } else {
      chartColor = .green
    }

    return ChartData(chartColor: chartColor, quotes: quotes)
  }

  private func updateChartData() {
    for (timeSection, quotes) in models {
      priceHistories[timeSection] = buildChartData(quotes: quotes)
    }

    DispatchQueue.main.async {
      self.chartData = self.priceHistories
    }
  }
}
