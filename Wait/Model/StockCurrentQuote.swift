// Created by kai_chen on 5/8/21.

import Foundation
import Money

// MARK: - StockCurrentQuoteBatch

public struct StockCurrentQuoteBatch: Codable {
  // MARK: Lifecycle

  public init(from decoder: Decoder) throws {
    // 1
    // Create a decoding container using DynamicCodingKeys
    // The container will contain all the JSON first level key
    let container = try decoder.container(keyedBy: DynamicCodingKeys.self)

    var tempQuotes: [String: StockCurrentQuote] = [:]

    // 2
    // Loop through each key (student ID) in container
    for key in container.allKeys {
      // Decode Student using key & keep decoded Student object in tempArray
      let decodedObject = try container.decode(StockCurrentQuote.self, forKey: DynamicCodingKeys(stringValue: key.stringValue)!)
      tempQuotes[key.stringValue] = decodedObject
    }

    // 3
    // Finish decoding all Student objects. Thus assign tempArray to array.
    quotes = tempQuotes
  }

  public init(quotes: [String: StockCurrentQuote]) {
    self.quotes = quotes
  }

  // MARK: Public

  public let quotes: [String: StockCurrentQuote]

  // MARK: Private

  // Define DynamicCodingKeys type needed for creating
  // decoding container from JSONDecoder
  private struct DynamicCodingKeys: CodingKey {
    // MARK: Lifecycle

    init?(stringValue: String) {
      self.stringValue = stringValue
    }

    init?(intValue: Int) {
      // We are not using this, thus just return nil
      return nil
    }

    // MARK: Internal

    // Use for string-keyed dictionary
    var stringValue: String
    // Use for integer-keyed dictionary
    var intValue: Int?
  }
}

// MARK: - StockCurrentQuote

public struct StockCurrentQuote: Codable {
  // MARK: Lifecycle

  public init(
    symbol: String,
    name: String,
    open: Money<USD>,
    high: Money<USD>,
    low: Money<USD>,
    close: Money<USD>,
    volume: String,
    datetime: Date,
    percentChange: String
  ) {
    self.symbol = symbol
    self.name = name
    self.open = open
    self.high = high
    self.low = low
    self.close = close
    self.volume = volume
    self.datetime = datetime
    self.percentChange = percentChange
  }

  // MARK: Public

  public let symbol: String
  public let name: String
  public let open: Money<USD>
  public let high: Money<USD>
  public let low: Money<USD>
  public let close: Money<USD>
  public let volume: String
  public let datetime: Date
  public let percentChange: String
}

public extension StockCurrentQuote {
  static var empty: Self {
    StockCurrentQuote(
      symbol: "empty",
      name: "Empty",
      open: 0,
      high: 0,
      low: 0,
      close: 0,
      volume: "0",
      datetime: Date(),
      percentChange: "0"
    )
  }
}
