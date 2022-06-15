// Created by kai_chen on 5/17/21.

import Money

// TODO(kai) - remove this placeholder
public struct ChartData {
  
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
