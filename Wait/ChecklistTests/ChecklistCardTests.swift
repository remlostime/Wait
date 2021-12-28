//
// Created by: kai_chen on 12/28/21.
// Copyright © 2021 Wait. All rights reserved.
//

import XCTest
import ComposableArchitecture
import Model
@testable import Checklist

class ChecklistCardTests: XCTestCase {
  func testCheckAction() {
    let state = ChecklistCardState(
      checklistItem: ChecklistItem(name: "first"),
      currentChecklistItemIndex: 0
    )

    let store = TestStore(
      initialState: state,
      reducer: ChecklistCardReducerBuilder.build(),
      environment: ChecklistCardEnvironment())

    store.send(.check) {
      $0.checklistItem.isChecked = true
      $0.currentChecklistItemIndex += 1
    }
  }

  func testUncheckAction() {
    let state = ChecklistCardState(
      checklistItem: ChecklistItem(name: "first"),
      currentChecklistItemIndex: 0
    )

    let store = TestStore(
      initialState: state,
      reducer: ChecklistCardReducerBuilder.build(),
      environment: ChecklistCardEnvironment())

    store.send(.uncheck) {
      $0.checklistItem.isChecked = false
      $0.currentChecklistItemIndex += 1
    }
  }
}
