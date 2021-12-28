//
// Created by: kai_chen on 12/27/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import Model
import Logging

public protocol ChecklistDataManager {
  func save(items: [ChecklistItem])
  func load() -> [ChecklistItem]?
}

public struct DefaultChecklistDataManager: ChecklistDataManager {

  public init() {}

  private var checklistItemURL: URL {
    let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    let url = URL(fileURLWithPath: path)
    let checklistItemURL = url.appendingPathComponent("checklist-items.json")

    return checklistItemURL
  }

  public func save(items: [ChecklistItem]) {
    guard let data = try? JSONEncoder().encode(items) else {
      Logger.shared.error("failed to encode checklist items")
      return
    }

    do {
      try data.write(to: checklistItemURL)
    } catch {
      Logger.shared.error("failed to save checklist item. error: \(error.localizedDescription)")
    }
  }

  public func load() -> [ChecklistItem]? {
    guard let data = try? Data(contentsOf: checklistItemURL) else {
      Logger.shared.error("failed to get checklist item data")
      return nil
    }

    if let checklistItems = try? JSONDecoder().decode([ChecklistItem].self, from: data) {
      return checklistItems
    } else {
      Logger.shared.error("failed to decode checklist item")
      return nil
    }
  }
}
