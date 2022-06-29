//
// Created by: Kai Chen on 6/28/22.
// Copyright © 2021 Wait. All rights reserved.
//

import CacheService
import Foundation
import Logging
import Model

public class ChecklistStorage {
  // MARK: Lifecycle

  public init(name: String) {
    storage = Storage<[ChecklistItem]>(name: name)
  }

  // MARK: Public

  public func checklistItems() -> [ChecklistItem] {
    var checklistItems = ChecklistItem.allItems

    do {
      checklistItems = try storage.value()
    } catch {
      Logger.shared.error("Failed to get checklistItems. Error: \(error.localizedDescription)")
    }

    return checklistItems
  }

  public func save(checklistItems: [ChecklistItem]) {
    do {
      try storage.saveValue(checklistItems)
    } catch {
      Logger.shared.error("Failed to save checklistItems. Error: \(error.localizedDescription)")
    }
  }

  // MARK: Private

  private let storage: Storage<[ChecklistItem]>
}
