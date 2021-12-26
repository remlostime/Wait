//
// Created by: kai_chen on 6/6/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Alamofire
import Combine
import Foundation
import Logging
import Model

public final class StockCurrentQuoteNetworkClient {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  public func fetchDetails(stock: Stock) -> AnyPublisher<StockCurrentQuote, Error> {
    guard let url = buildStockQuoteURL(stock: stock) else {
      return Fail(error: URLError(.badURL))
        .eraseToAnyPublisher()
    }

    return URLSession.shared
      .dataTaskPublisher(for: url)
      .map(\.data)
      .decode(type: StockCurrentQuote.self, decoder: decoder)
      .eraseToAnyPublisher()
  }

  public func fetchDetails(stocks: [Stock]) -> AnyPublisher<StockCurrentQuoteBatch, Error> {
    guard let url = buildStockQuoteURL(stocks: stocks) else {
      return Fail(error: URLError(.badURL))
        .eraseToAnyPublisher()
    }

    return URLSession.shared
      .dataTaskPublisher(for: url)
      .map(\.data)
      .decode(type: StockCurrentQuoteBatch.self, decoder: decoder)
      .eraseToAnyPublisher()
  }

  // MARK: Private

  private lazy var decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-mm-dd"
    decoder.dateDecodingStrategy = .formatted(dateFormatter)
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    return decoder
  }()

  private func buildStockQuoteURL(stocks: [Stock]) -> URL? {
    let symbols = stocks.map { $0.symbol }
    let params = [
      "symbol": symbols.joined(separator: ","),
    ]

    let url = NetworkingURLBuilder.buildURL(api: "quote", params: params)

    return url
  }

  private func buildStockQuoteURL(stock: Stock) -> URL? {
    let params = [
      "symbol": stock.symbol,
    ]

    let url = NetworkingURLBuilder.buildURL(api: "quote", params: params)

    return url
  }
}
