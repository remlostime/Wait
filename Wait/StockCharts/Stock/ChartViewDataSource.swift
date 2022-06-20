// Created by kai_chen on 5/17/21.

import Money
import SwiftUI
import Model
import Charts

// MARK: - ChartData

public struct ChartData {
  public let chartColor: Color
  public let points: [CGPoint]
  
  public init(chartColor: Color, quotes: [StockQuote]) {
    self.chartColor = chartColor
    
    var index = 0
    var points: [CGPoint] = []
    for quote in quotes {
      points.append(CGPoint(x: Double(index), y: quote.close.amountDoubleValue))
      index += 1
    }
    self.points = points
  }
}

extension CGFloat: Plottable {
  public init?(primitivePlottable: Double) {
    self = CGFloat(primitivePlottable)
  }
  
  public var primitivePlottable: Double {
    Double(self)
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
