// Created by kai_chen on 5/17/21.

import Foundation
import Alamofire
import SwiftyJSON

class PriceHistoryNetworkClient {
  func fetchHistory(
    symbol: String,
    timeSection: TimeSection,
    completion: @escaping (([StockQuote]) -> Void))
  {
    guard let url = makeHistoryURL(symbol: symbol, timeSection: timeSection) else {
      logger.error("Error to fetch price history")
      return
    }

    AF.request(url).validate().responseData { response in
      switch response.result {
        case .success(let data):
          let decoder = JSONDecoder()
          decoder.dateDecodingStrategy = .formatted(timeSection.dateFormatter)

          guard
            let json = try? JSON(data: data),
            let rawData = try? json[timeSection.priceHistoryResourceKey].rawData(),
            let stockQuotesDict = try? decoder.decode([String: StockQuote].self, from: rawData) else
          {
            logger.error("Failed to decode price history")
            completion([])
            return
          }

          var stockQuotes: [StockQuote] = []
          for (dateStr, quote) in stockQuotesDict {
            guard let date = timeSection.dateFormatter.date(from: dateStr) else {
              continue
            }

            let stockQuote = StockQuote(
              open: quote.open,
              high: quote.high,
              low: quote.low,
              close: quote.close,
              date: date)

            stockQuotes.append(stockQuote)
          }

          stockQuotes.sort(by: \.date)

          completion(stockQuotes)
        case .failure(let error):
          logger.error("Failed to decode price history: \(error.localizedDescription)")
          completion([])
      }
    }
  }

  private func makeHistoryURL(symbol: String, timeSection: TimeSection) -> URL? {
    var priceHistoryAPIParams = timeSection.priceHistoryAPIParams
    priceHistoryAPIParams["symbol"] = symbol

    let url = NetworkingURLBuilder.buildURL(api: "query", params: priceHistoryAPIParams)

    return url
  }
}
