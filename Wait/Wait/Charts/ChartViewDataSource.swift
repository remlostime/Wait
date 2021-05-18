// Created by kai_chen on 5/17/21.

import Charts
import Money

// MARK: - ChartViewDataSource
public protocol ChartViewDataSource {
  var chartData: [TimeSection: ChartData] { get }

  /// The price label value
  var currentPrice: Money<USD> { get }

  var delegate: ChartViewDataSourceDelegate? { get }
  func setDelegate(delegate: ChartViewDataSourceDelegate)

  /// Fetch chart data for `timeSections`
  func fetchData(for timeSections: [TimeSection])

  /// By default, we show the last data point in the chart for price label.
  /// If we need other data source to provide that data. We need to implement this func.
  func fetchCurrentQuotes()
}

// MARK: - ChartViewDataSourceDelegate
public protocol ChartViewDataSourceDelegate: AnyObject {
  func dataDidUpdate(_ data: [TimeSection: ChartData])
  func currentPriceDidUpdate(_ currentPrice: Money<USD>)
}
