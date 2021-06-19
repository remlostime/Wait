//
// Created by: kai_chen on 6/6/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Alamofire
import Foundation
import Model

final class StockCurrentQuoteNetworkClient {
  // MARK: Internal

  func fetchStockDetails(stock: Stock, completion: @escaping ((Stock) -> Void)) {
    guard let url = buildStockQuoteURL(stock: stock) else {
      return
    }

    AF.request(url).validate().responseData { response in
      switch response.result {
        case let .success(data):
          let decoder = JSONDecoder()
          let dateFormatter = DateFormatter()
          dateFormatter.dateFormat = "yyyy-mm-dd"
          decoder.dateDecodingStrategy = .formatted(dateFormatter)

          guard
            let stockQuote = try? decoder.decode(StockCurrentQuote.self, from: data)
          else {
            logger.error("Failed to decode stock quote")
            return
          }

          // TODO(kai) - fix change percent
          let newStock = Stock(
            symbol: stockQuote.symbol,
            name: stock.name,
            currentPrice: stockQuote.close,
            expectedPrice: stock.expectedPrice,
            changePercent: "",
            priceChartImage: nil
          )

          completion(newStock)
        case let .failure(error):
          logger.error("Failed to fetch stock quote: \(error.localizedDescription)")
      }
    }
  }

  // MARK: Private

  private func buildStockQuoteURL(stock: Stock) -> URL? {
    let params = [
      "symbol": stock.symbol,
    ]

    let url = NetworkingURLBuilder.buildURL(api: "quote", params: params)

    return url
  }
}
