//
// Created by: kai_chen on 7/20/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import Model
import CloudKit

final class CloudNetworkClient {

  private let container: CKContainer
  private let publicDB: CKDatabase
  private let privateDB: CKDatabase

  private let StockRecordType = "Stock"

  init() {
    container = CKContainer.default()
    publicDB = container.publicCloudDatabase
    privateDB = container.privateCloudDatabase
  }

  func fetchStocks(completion: @escaping ((Result<[Stock], Error>) -> Void)) {
    let predicate = NSPredicate(value: true)
    let query = CKQuery(recordType: StockRecordType, predicate: predicate)

    privateDB.perform(query, inZoneWith: CKRecordZone.default().zoneID) { records, error in
      if let error = error {
        DispatchQueue.main.async {
          completion(.failure(error))
        }

        return
      }

      guard let records = records else {
        return
      }

      let stocks = records.compactMap { record in
        Stock(from: record)
      }

      DispatchQueue.main.async {
        completion(.success(stocks))
      }
    }
  }

  func saveStock(_ stock: Stock) {
    let record = CKRecord(recordType: StockRecordType)
    record["symbol"] = stock.symbol
    record["name"] = stock.name
    record["expectedPrice"] = stock.expectedPrice.description
    record["memo"] = stock.memo

    privateDB.save(record) { _, _ in
      logger.verbose("Stock: \(stock.symbol) is saved successfully")
    }
  }
}
