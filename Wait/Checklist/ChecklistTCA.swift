//
// Created by: kai_chen on 12/12/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import ComposableArchitecture
import Model

public enum ChecklistAction {
  case goBack
  case startOver
}

public struct ChecklistState: Equatable {
  var currentChecklistItemIndex: Int = 0
  var checklistItems: [ChecklistItem]

  public init(checklistItems: [ChecklistItem]) {
    self.checklistItems = checklistItems
  }
}

extension ChecklistState {
  var progress: String {
    "\(currentChecklistItemIndex + 1) / \(checklistItems.count)"
  }
}

public struct ChecklistEnvironment {}

public typealias ChecklistReducer = Reducer<ChecklistState, ChecklistAction, ChecklistEnvironment>

public struct ChecklistReducerBuilder {
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




