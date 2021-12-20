//
// Created by: kai_chen on 12/16/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Foundation
import Model

// MARK: - ChecklistListAction

public enum ChecklistListAction {
  case check(index: Int)
  case uncheck(index: Int)
}

// MARK: - ChecklistListState

public struct ChecklistListState: Equatable {
  var checklistItems: [ChecklistItem]
}

// MARK: - ChecklistListEnvironment

public struct ChecklistListEnvironment {}

public typealias ChecklistListReducer = Reducer<ChecklistListState, ChecklistListAction, ChecklistListEnvironment>

// MARK: - ChecklistListReducerBuilder

public enum ChecklistListReducerBuilder {
  static func build() -> ChecklistListReducer {
    let reducer = ChecklistListReducer { state, action, _ in
      switch action {
        case let .check(index):
          state.checklistItems[index].isChecked = true
          return .none
        case let .uncheck(index):
          state.checklistItems[index].isChecked = false
          return .none
      }
    }

    return reducer
  }
}
