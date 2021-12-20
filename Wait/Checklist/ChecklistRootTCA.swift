//
// Created by: kai_chen on 12/12/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Foundation

// MARK: - ChecklistRootAction

public enum ChecklistRootAction {
  case cardAction(ChecklistCardAction)
  case rootAction(ChecklistAction)
  case listAction(ChecklistListAction)
}

// MARK: - ChecklistRootState

public struct ChecklistRootState {
  // MARK: Lifecycle

  public init(rootState: ChecklistState) {
    self.rootState = rootState
  }

  // MARK: Internal

  var rootState: ChecklistState

  var listState: ChecklistListState {
    get {
      ChecklistListState(checklistItems: rootState.checklistItems)
    }

    set {
      rootState.checklistItems = newValue.checklistItems
    }
  }

  var cardState: ChecklistCardState {
    get {
      let item = rootState.checklistItems[rootState.currentChecklistItemIndex]
      return ChecklistCardState(checklistItem: item, currentChecklistItemIndex: rootState.currentChecklistItemIndex)
    }

    set {
      let item = newValue.checklistItem
      rootState.checklistItems[rootState.currentChecklistItemIndex] = item
      rootState.currentChecklistItemIndex = newValue.currentChecklistItemIndex % rootState.checklistItems.count
    }
  }
}

// MARK: - ChecklistRootEnvironment

public struct ChecklistRootEnvironment {
  public init() {}
}

public typealias ChecklistRootReducer = Reducer<ChecklistRootState, ChecklistRootAction, ChecklistRootEnvironment>

// MARK: - ChecklistRootReducerBuilder

public enum ChecklistRootReducerBuilder {
  public static func build() -> ChecklistRootReducer {
    let cardReducer = ChecklistCardReducerBuilder.build()
    let checklistReducer = ChecklistReducerBuilder.build()
    let listReducer = ChecklistListReducerBuilder.build()

    let reducer = ChecklistRootReducer.combine(
      cardReducer.pullback(
        state: \.cardState,
        action: /ChecklistRootAction.cardAction,
        environment: { _ in
          ChecklistCardEnvironment()
        }
      ),

      checklistReducer.pullback(
        state: \.rootState,
        action: /ChecklistRootAction.rootAction,
        environment: { _ in
          ChecklistEnvironment()
        }
      ),

      listReducer.pullback(
        state: \.listState,
        action: /ChecklistRootAction.listAction,
        environment: { _ in
        ChecklistListEnvironment()
      })
    )

    return reducer
  }
}
