// Created by kai_chen on 5/17/21.

import CacheService
import Foundation
import Logging

// TODO(kai) - Update ChartCache
class ChartCache<ChartData> {
  
  // MARK: Lifecycle

  init(cacheName: String, symbol: String) {
    self.symbol = symbol
    self.cache = Cache<String, ChartData>()
    
//    storage = try? Storage(
//      diskConfig: diskConfig,
//      memoryConfig: memoryConfig,
//      transformer: TransformerFactory.forCodable(ofType: ChartData.self)
//    )
  }

  // MARK: Internal

  func getChartData(completion: @escaping ((ChartData?) -> Void)) {
//    storage?.async.object(forKey: symbol, completion: { result in
//      switch result {
//        case let .value(chartData):
//          Logger.shared.verbose("Successfully fetch chart data for \(self.symbol)")
//          completion(chartData)
//        case let .error(error):
//          Logger.shared.error("Failed to fetch chart data for \(self.symbol). Error: \(error.localizedDescription)")
//          completion(nil)
//      }
//    })
  }

  func setChartData(_ data: ChartData) {
//    storage?.async.setObject(data, forKey: symbol, completion: { result in
//      switch result {
//        case .value:
//          Logger.shared.verbose("Successfully save chart data for \(self.symbol)")
//        case let .error(error):
//          Logger.shared.error("Failed to save chart data for \(self.symbol). Error: \(error.localizedDescription)")
//      }
//    })
  }

  // MARK: Private

  private let cache: Cache<String, ChartData>
  private let symbol: String
}
