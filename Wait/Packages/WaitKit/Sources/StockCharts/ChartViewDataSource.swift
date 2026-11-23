// Created by kai_chen on 5/17/21.

import Charts
import Model
import Money
import SwiftUI

// MARK: - ChartPoint

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

// MARK: - ChartPoint + Identifiable

extension ChartPoint: Identifiable {
  public var id: Int {
    index
  }
}

// MARK: - CGPoint + Identifiable

extension CGPoint: Identifiable {
  public var id: Double {
    x
  }
}
