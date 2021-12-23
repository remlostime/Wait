//
// Created by: kai_chen on 10/9/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Foundation
import Model

// MARK: - ChecklistEditAction

public enum ChecklistEditAction {
  case addItem
  case save
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
  public init() {}
}

// MARK: - ChecklistEditReducerBuilder

public typealias ChecklistEditReducer = Reducer<ChecklistEditState, ChecklistEditAction, ChecklistEditEnvironment>

// MARK: - ChecklistEditReducerBuilder

public enum ChecklistEditReducerBuilder {
  public static func build() -> ChecklistEditReducer {
    let settingsReducer = ChecklistEditReducer { state, action, _ in
      switch action {
        case .addItem:
          state.items.insert(ChecklistItem(name: ""), at: 0)
          return .none
        case .save:
          ChecklistCache.shared.saveItems(state.items)
          return .none
        case let .itemDidChange(index, text):
          state.items[index].name = text
          return .none
      }
    }

    return settingsReducer
  }
}
