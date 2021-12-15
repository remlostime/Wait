//
// Created by: kai_chen on 12/12/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Foundation
import Model

// MARK: - ChecklistAction

public enum ChecklistAction {
  case goBack
  case startOver
}

// MARK: - ChecklistState

public struct ChecklistState: Equatable {
  // MARK: Lifecycle

  public init(checklistItems: [ChecklistItem]) {
    self.checklistItems = checklistItems
  }

  // MARK: Internal

  var currentChecklistItemIndex: Int = 0
  var checklistItems: [ChecklistItem]
}

extension ChecklistState {
  var progress: String {
    "\(currentChecklistItemIndex + 1) / \(checklistItems.count)"
  }
}

// MARK: - ChecklistEnvironment

public struct ChecklistEnvironment {}

public typealias ChecklistReducer = Reducer<ChecklistState, ChecklistAction, ChecklistEnvironment>

// MARK: - ChecklistReducerBuilder

public enum ChecklistReducerBuilder {
  public static func build() -> ChecklistReducer {
    let checklistReducer = ChecklistReducer { state, action, _ in
      switch action {
        case .goBack:
          var index = state.currentChecklistItemIndex - 1
          if index < 0 {
            index = 0
          }
          state.currentChecklistItemIndex = index

          return .none
        case .startOver:
          state.currentChecklistItemIndex = 0

          return .none
      }
    }

    return checklistReducer
  }
}
