// Created by kai_chen on 5/17/21.

import Alamofire
import Foundation
import Logging
import Model
import Networking
import SwiftyJSON

class PriceHistoryNetworkClient {
  // MARK: Internal

  func fetchHistory(
    symbol: String,
    timeSection: TimeSection,
    completion: @escaping (([StockQuote]) -> Void)
  ) {
    guard let url = makeHistoryURL(symbol: symbol, timeSection: timeSection) else {
      Logger.shared.error("Error to fetch price history")
      return
    }

    AF.request(url).validate().responseData { response in
      switch response.result {
        case let .success(data):
          let decoder = JSONDecoder()
          decoder.dateDecodingStrategy = .formatted(timeSection.dateFormatter)

          guard
            let json = try? JSON(data: data),
            let rawData = try? json["values"].rawData()
          else {
            return
          }

          do {
            let stockQuotes = try decoder.decode([StockQuote].self, from: rawData)
            completion(stockQuotes.reversed())
          } catch {
            Logger.shared.error("Failed to decode price history: \(error.localizedDescription)")
            completion([])
          }
        case let .failure(error):
          Logger.shared.error("Failed to decode price history: \(error.localizedDescription)")
          completion([])
      }
    }
  }

  // MARK: Private

  private func makeHistoryURL(symbol: String, timeSection: TimeSection) -> URL? {
    let priceHistoryAPIParams = [
      "symbol": symbol,
      "outputsize": String(timeSection.dataSize),
      "interval": timeSection.dataInterval,
    ]

    let url = NetworkingURLBuilder.buildURL(api: "time_series", params: priceHistoryAPIParams)

    return url
  }
}
