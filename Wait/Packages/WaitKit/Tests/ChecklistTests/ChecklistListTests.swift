//
// Created by: kai_chen on 12/28/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Foundation
import Model
import Testing
@testable import Checklist

// MARK: - ChecklistListTests

@MainActor
@Suite("ChecklistListReducer")
struct ChecklistListTests {
  // MARK: Internal

  @Test("checking then unchecking every item toggles isChecked")
  func checkAndUncheck() async {
    let store = TestStore(initialState: ChecklistListReducer.State(checklistItems: items)) {
      ChecklistListReducer(save: { _ in })
    }

    for index in items.indices {
      await store.send(.check(index: index)) {
        $0.checklistItems[index].isChecked = true
      }
      await store.send(.uncheck(index: index)) {
        $0.checklistItems[index].isChecked = false
      }
    }
  }

  @Test("every toggle persists the whole list")
  func persistsOnEveryToggle() async {
    let saved = LockIsolated<[[ChecklistItem]]>([])
    let store = TestStore(initialState: ChecklistListReducer.State(checklistItems: items)) {
      ChecklistListReducer(save: { items in saved.withValue { $0.append(items) } })
    }

    await store.send(.check(index: 1)) {
      $0.checklistItems[1].isChecked = true
    }

    #expect(saved.value.count == 1)
    #expect(saved.value.last?.map(\.isChecked) == [false, true])
  }

  // MARK: Private

  private let items = [
    ChecklistItem(name: "first", id: UUID(0)),
    ChecklistItem(name: "second", id: UUID(1)),
  ]
}
