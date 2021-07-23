// Created by kai_chen on 5/8/21.

import CloudKit
import Foundation
import Money

// MARK: - StockCurrentQuote

public struct StockCurrentQuote: Codable {
  // MARK: Lifecycle

  public init(from record: CKRecord) {
    symbol = (record["symbol"] as? String) ?? ""
    name = (record["name"] as? String) ?? ""
    let openStr = (record["open"] as? String) ?? "0"
    open = Money<USD>(stringLiteral: openStr)
    let highStr = (record["high"] as? String) ?? "0"
    high = Money<USD>(stringLiteral: highStr)
    let lowStr = (record["low"] as? String) ?? "0"
    low = Money<USD>(stringLiteral: lowStr)
    let closeStr = (record["close"] as? String) ?? "0"
    close = Money<USD>(stringLiteral: closeStr)
    volume = (record["volume"] as? String) ?? ""
    datetime = (record["datetime"] as? Date) ?? Date()
    percentChange = (record["percentChange"] as? String) ?? ""
  }

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

  static var container: CKContainer {
    CKContainer.default()
  }

  static var publicDB: CKDatabase {
    container.publicCloudDatabase
  }

  static var privateDB: CKDatabase {
    container.privateCloudDatabase
  }

  static func fetch(recordID: CKRecord.ID, completion: @escaping ((Result<StockCurrentQuote, Error>) -> Void)) {
    let _privateDB = privateDB

    _privateDB.fetch(withRecordID: recordID) { record, error in
      if let error = error {
        completion(.failure(error))
        return
      }

      guard let record = record else {
        completion(.failure(NSError(domain: "stockCurrentQuote", code: 0, userInfo: nil)))
        return
      }

      let stockCurrentQuote = StockCurrentQuote(from: record)
      completion(.success(stockCurrentQuote))
    }
  }
}
