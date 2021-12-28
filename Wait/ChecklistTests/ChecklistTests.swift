//
// Created by: kai_chen on 12/12/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Model
import XCTest
@testable import Checklist

class ChecklistTests: XCTestCase {
  func testChecklistState() {
    let state = ChecklistState(
      checklistItems: [
        ChecklistItem(name: "first"),
        ChecklistItem(name: "second"),
      ],
      currentChceklistItemIndex: 1
    )

    XCTAssertEqual(state.progress, "\(state.currentChecklistItemIndex + 1) / \(state.checklistItems.count)")
  }

  func testGoBack() {
    let state = ChecklistState(
      checklistItems: [
        ChecklistItem(name: "first"),
        ChecklistItem(name: "second"),
      ],
      currentChceklistItemIndex: 1
    )

    let store = TestStore(
      initialState: state,
      reducer: ChecklistReducerBuilder.build(),
      environment: ChecklistEnvironment()
    )

    store.send(.goBack) {
      $0.currentChecklistItemIndex -= 1
    }

    store.send(.goBack) {
      $0.currentChecklistItemIndex = 0
    }
  }

  func testStartOver() {
    let state = ChecklistState(
      checklistItems: [
        ChecklistItem(name: "first"),
        ChecklistItem(name: "second"),
      ],
      currentChceklistItemIndex: 1
    )

    let store = TestStore(
      initialState: state,
      reducer: ChecklistReducerBuilder.build(),
      environment: ChecklistEnvironment()
    )

    store.send(.startOver) {
      $0.currentChecklistItemIndex = 0
    }
  }
}
