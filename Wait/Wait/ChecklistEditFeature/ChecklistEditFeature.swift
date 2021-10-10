//
// Created by: kai_chen on 10/9/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import ComposableArchitecture
import Model

enum ChecklistEditAction {
  case addItem
  case save
  case itemDidChange(index: Int, text: String)
}

struct ChecklistEditState: Equatable {
  var items: [ChecklistItem] = ChecklistCache.shared.getItems()
}

struct ChecklistEditEnvironment {

}

let settingsReducer = Reducer<ChecklistEditState, ChecklistEditAction, ChecklistEditEnvironment> { state, action, environment in
  switch action {
    case .addItem:
      state.items.insert(ChecklistItem(name: ""), at: 0)
      return .none
    case .save:
      ChecklistCache.shared.saveItems(state.items)
      return .none
    case .itemDidChange(let index, let text):
      state.items[index].name = text
      return .none
  }
}
