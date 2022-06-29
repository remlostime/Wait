//
// Created by: Kai Chen on 6/28/22.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import CacheService
import Model
import Logging

public class ChecklistStorage {
  private let storage: Storage<[ChecklistItem]>
  
  public init(name: String) {
    storage = Storage<[ChecklistItem]>(name: name)
  }
  
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
}
