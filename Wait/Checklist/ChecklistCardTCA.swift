//
// Created by: kai_chen on 12/12/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import ComposableArchitecture
import Model

public enum ChecklistCardAction {
  case check
  case uncheck
}

public struct ChecklistCardState: Equatable {
  var checklistItem: ChecklistItem
  var currentChecklistItemIndex: Int
}

public struct ChecklistCardEnvironment {}

public typealias ChecklistCardReducer = Reducer<ChecklistCardState, ChecklistCardAction, ChecklistCardEnvironment>

public struct ChecklistCardReducerBuilder {
  static func build() -> ChecklistCardReducer {
    let reducer = ChecklistCardReducer { state, action, _ in
      switch action {
        case .check:
          state.checklistItem.isChecked = true
          state.currentChecklistItemIndex += 1
          return .none
        case .uncheck:
          state.checklistItem.isChecked = false
          state.currentChecklistItemIndex += 1
          return .none
      }
    }

    return reducer
  }
}
