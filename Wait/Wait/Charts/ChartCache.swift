// Created by kai_chen on 5/17/21.

import Cache
import Foundation

class ChartCache<ChartData: Codable> {
  // MARK: Lifecycle
  
  init(cacheName: String, symbol: String) {
    let diskUrl = try? FileManager.default.url(
      for: .documentDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    
    let diskConfig = DiskConfig(name: cacheName, directory: diskUrl)

    let memoryConfig = MemoryConfig()

    self.symbol = symbol
    storage = try? Storage(
      diskConfig: diskConfig,
      memoryConfig: memoryConfig,
      transformer: TransformerFactory.forCodable(ofType: ChartData.self)
    )
  }

  // MARK: Internal

  func getChartData(completion: @escaping ((ChartData?) -> Void)) {
    storage?.async.object(forKey: symbol, completion: { result in
      switch result {
        case let .value(chartData):
          logger.verbose("Successfully fetch chart data for \(self.symbol)")
          completion(chartData)
        case let .error(error):
          logger.error("Failed to fetch chart data for \(self.symbol). Error: \(error.localizedDescription)")
          completion(nil)
      }
    })
  }

  func setChartData(_ data: ChartData) {
    storage?.async.setObject(data, forKey: symbol, completion: { result in
      switch result {
        case .value:
          logger.verbose("Successfully save chart data for \(self.symbol)")
        case let .error(error):
          logger.error("Failed to save chart data for \(self.symbol). Error: \(error.localizedDescription)")
      }
    })
  }

  // MARK: Private

  private let storage: Storage<String, ChartData>?
  private let symbol: String
}
