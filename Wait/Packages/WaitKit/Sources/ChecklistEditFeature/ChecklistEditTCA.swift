//
// Created by: kai_chen on 10/9/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Foundation
import Logging
import Model
import SwiftUI

// MARK: - ChecklistEditAction

public enum ChecklistEditAction {
  case addItem
  case save
  case load
  case itemDidChange(index: Int, text: String)
}

// MARK: - ChecklistEditState

public struct ChecklistEditState: Equatable {
  // MARK: Lifecycle

  public init(items: [ChecklistItem]) {
    self.items = items
  }

  // MARK: Internal

  var items: [ChecklistItem]
}

// MARK: - ChecklistEditEnvironment

public struct ChecklistEditEnvironment {
  // MARK: Lifecycle

  public init(checklistDataManager: ChecklistDataManager, uuid: @escaping (() -> UUID)) {
    self.checklistDataManager = checklistDataManager
    self.uuid = uuid
  }

  // MARK: Internal

  let checklistDataManager: ChecklistDataManager
  let uuid: () -> UUID
}

// MARK: - ChecklistEditReducerBuilder

public typealias ChecklistEditReducer = Reducer<ChecklistEditState, ChecklistEditAction, ChecklistEditEnvironment>

// MARK: - ChecklistEditReducerBuilder

public enum ChecklistEditReducerBuilder {
  public static func build() -> ChecklistEditReducer {
    let reducer = ChecklistEditReducer { state, action, environment in
      switch action {
        case .addItem:
          state.items.insert(ChecklistItem(name: "", id: environment.uuid()), at: 0)
          return .none
        case .load:
          if let checklistItems = environment.checklistDataManager.load() {
            state.items = checklistItems
          }
          return .none
        case .save:
          environment.checklistDataManager.save(items: state.items)
          return .none
        case let .itemDidChange(index, text):
          state.items[index].name = text
          return .none
      }
    }

    return reducer
  }
}
