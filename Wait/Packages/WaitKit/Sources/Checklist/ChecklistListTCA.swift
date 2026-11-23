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
  // MARK: Lifecycle

  public init(checklistItems: [ChecklistItem]) {
    self.checklistItems = checklistItems
  }

  // MARK: Internal

  var checklistItems: [ChecklistItem]
}

// MARK: - ChecklistListEnvironment

public struct ChecklistListEnvironment {
  // MARK: Lifecycle

  public init(checklistStorage: ChecklistStorage) {
    self.checklistStorage = checklistStorage
  }

  // MARK: Public

  public let checklistStorage: ChecklistStorage
}

public typealias ChecklistListReducer = Reducer<ChecklistListState, ChecklistListAction, ChecklistListEnvironment>

// MARK: - ChecklistListReducerBuilder

public enum ChecklistListReducerBuilder {
  public static func build() -> ChecklistListReducer {
    let reducer = ChecklistListReducer { state, action, environment in
      switch action {
        case let .check(index):
          state.checklistItems[index].isChecked = true
          environment.checklistStorage.save(checklistItems: state.checklistItems)

          return .none
        case let .uncheck(index):
          state.checklistItems[index].isChecked = false
          environment.checklistStorage.save(checklistItems: state.checklistItems)

          return .none
      }
    }

    return reducer
  }
}
