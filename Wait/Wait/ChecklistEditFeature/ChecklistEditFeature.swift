//
// Created by: kai_chen on 10/9/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Foundation
import Model

// MARK: - ChecklistEditAction

enum ChecklistEditAction {
  case addItem
  case save
  case itemDidChange(index: Int, text: String)
}

// MARK: - ChecklistEditState

struct ChecklistEditState: Equatable {
  var items: [ChecklistItem] = ChecklistCache.shared.getItems()
}

// MARK: - ChecklistEditEnvironment

struct ChecklistEditEnvironment {}

let settingsReducer = Reducer<ChecklistEditState, ChecklistEditAction, ChecklistEditEnvironment> { state, action, _ in
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
