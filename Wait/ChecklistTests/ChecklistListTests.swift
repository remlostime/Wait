//
// Created by: kai_chen on 12/28/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Model
import XCTest
@testable import Checklist

class ChecklistListTests: XCTestCase {
  func testCheckAndUncheckAction() {
    let state = ChecklistListState(checklistItems: [
      ChecklistItem(name: "first", id: UUID()),
      ChecklistItem(name: "second", id: UUID()),
    ])

    let store = TestStore(
      initialState: state,
      reducer: ChecklistListReducerBuilder.build(),
      environment: ChecklistListEnvironment()
    )

    for index in 0 ..< state.checklistItems.count {
      store.send(.check(index: index)) {
        $0.checklistItems[index].isChecked = true
      }

      store.send(.uncheck(index: index)) {
        $0.checklistItems[index].isChecked = false
      }
    }
  }
}
