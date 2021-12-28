//
// Created by: kai_chen on 12/28/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import ChecklistEditFeature
import Model

// MARK: - MockChecklistDataManager

class MockChecklistDataManager: ChecklistDataManager {
  // MARK: Lifecycle

  init(items: [ChecklistItem] = []) {
    self.items = items
  }

  // MARK: Internal

  var items: [ChecklistItem] = []

  func save(items: [ChecklistItem]) {
    self.items = items
  }

  func load() -> [ChecklistItem]? {
    items
  }
}
