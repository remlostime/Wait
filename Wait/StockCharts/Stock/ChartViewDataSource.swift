// Created by kai_chen on 5/17/21.

import Charts
import Model
import Money
import SwiftUI

public struct ChartPoint {
  public let index: Int
  public let quote: StockQuote
}

// MARK: - ChartData

public struct ChartData {
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

// MARK: - CGFloat + Plottable

extension CGFloat: Plottable {
  // MARK: Lifecycle

  public init?(primitivePlottable: Double) {
    self = CGFloat(primitivePlottable)
  }

  // MARK: Public

  public var primitivePlottable: Double {
    Double(self)
  }
}

// MARK: - CGPoint + Identifiable

extension ChartPoint: Identifiable {
  public var id: Int {
    index
  }
}

extension CGPoint: Identifiable {
  public var id: Double {
    x
  }
}

// MARK: - ChartViewDataSource

public protocol ChartViewDataSource {
  var chartData: [TimeSection: ChartData] { get }

  /// The price label value
  var currentPrice: Money<USD> { get }

  var delegate: ChartViewDataSourceDelegate? { get }
  func setDelegate(delegate: ChartViewDataSourceDelegate)

  /// Fetch chart data for `timeSections`
  func fetchData(for timeSections: [TimeSection])
}

// MARK: - ChartViewDataSourceDelegate

public protocol ChartViewDataSourceDelegate: AnyObject {
  func dataDidUpdate(_ data: [TimeSection: ChartData])
  func currentPriceDidUpdate(_ currentPrice: Money<USD>)
}
