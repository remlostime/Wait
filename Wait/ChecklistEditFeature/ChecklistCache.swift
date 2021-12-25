//
// Created by: kai_chen on 10/10/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Cache
import Foundation
import Logging
import Model

class ChecklistCache {
  // MARK: Lifecycle

  private init() {}

  // MARK: Internal

  static let shared = ChecklistCache()

  func getItems() -> [ChecklistItem] {
    guard let items = try? storage?.object(forKey: key) else {
      return []
    }

    return items
  }

  func saveItems(_ items: [ChecklistItem]) {
    storage?.async.setObject(items, forKey: key) { result in
      switch result {
        case .value:
          Logger.shared.verbose("Successfully store checklist")
        case let .error(error):
          Logger.shared.error("Failed to store checklist: \(error.localizedDescription)")
      }
    }
  }

  // MARK: Private

  private let key = "checklist"

  private lazy var storage: Storage<String, [ChecklistItem]>? = {
    let diskUrl = try? FileManager.default.url(
      for: .documentDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )

    let diskConfig = DiskConfig(name: "checklist", directory: diskUrl)

    let memoryConfig = MemoryConfig()

    let storage = try? Storage<String, [ChecklistItem]>(
      diskConfig: diskConfig,
      memoryConfig: memoryConfig,
      transformer: TransformerFactory.forCodable(ofType: [ChecklistItem].self)
    )

    return storage
  }()
}
