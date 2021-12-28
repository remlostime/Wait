//
// Created by: kai_chen on 10/9/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Foundation
import Model
import SwiftUI
import Logging

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
  let checklistDataManager: ChecklistDataManager

  public init(checklistDataManager: ChecklistDataManager) {
    self.checklistDataManager = checklistDataManager
  }
}

// MARK: - ChecklistEditReducerBuilder

public typealias ChecklistEditReducer = Reducer<ChecklistEditState, ChecklistEditAction, ChecklistEditEnvironment>

// MARK: - ChecklistEditReducerBuilder

public enum ChecklistEditReducerBuilder {
  public static func build() -> ChecklistEditReducer {
    let reducer = ChecklistEditReducer { state, action, environment in
      switch action {
        case .addItem:
          state.items.insert(ChecklistItem(name: ""), at: 0)
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
