// Created by kai_chen on 5/17/21.

import CacheService
import Foundation
import Logging

class ChartCache<ChartData: Codable> {
  // MARK: Lifecycle

  init(cacheName: String, symbol: String) {
    self.symbol = symbol
    storage = Storage<ChartData>(name: "cache-\(cacheName)-\(symbol)")
  }

  // MARK: Internal
  
  private func getChartDataFromDisk() {
    do {
      let chartData = try storage.value()
      self.chartData = chartData
    } catch {
      Logger.shared.error("Failed to get chartData from disk. Error: \(error.localizedDescription)")
    }
  }

  func getChartData() -> ChartData? {
    if chartData == nil {
      getChartDataFromDisk()
    }
    
    return chartData
  }

  func setChartData(_ data: ChartData) {
    chartData = data
    do {
      try storage.saveValue(data)
    } catch {
      Logger.shared.error("Failed to save chartData to disk. Error: \(error.localizedDescription)")
    }
  }

  // MARK: Private

  private var chartData: ChartData?
  private let storage: Storage<ChartData>
  private let symbol: String
}
