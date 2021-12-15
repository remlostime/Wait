//
// Created by: kai_chen on 12/12/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import ComposableArchitecture

public enum ChecklistRootAction {
  case cardAction(ChecklistCardAction)
  case rootAction(ChecklistAction)
}

public struct ChecklistRootState {
  var rootState: ChecklistState

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

  public init(rootState: ChecklistState) {
    self.rootState = rootState
  }
}

public struct ChecklistRootEnvironment {
  public init() {}
}

public typealias ChecklistRootReducer = Reducer<ChecklistRootState, ChecklistRootAction, ChecklistRootEnvironment>

public struct ChecklistRootReducerBuilder {
  public static func build() -> ChecklistRootReducer {
    let cardReducer = ChecklistCardReducerBuilder.build()
    let checklistReducer = ChecklistReducerBuilder.build()

    let reducer = ChecklistRootReducer.combine(
      cardReducer.pullback(
        state: \.cardState,
        action: /ChecklistRootAction.cardAction,
        environment: { _ in
          ChecklistCardEnvironment()
        }),

      checklistReducer.pullback(
        state: \.rootState,
        action: /ChecklistRootAction.rootAction,
        environment: { _ in
          ChecklistEnvironment()
        })
    )

    return reducer
  }
}
