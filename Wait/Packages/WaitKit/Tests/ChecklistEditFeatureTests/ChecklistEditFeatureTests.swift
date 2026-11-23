//
// Created by: kai_chen on 12/23/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Foundation
import Model
import Testing
@testable import ChecklistEditFeature

// MARK: - ChecklistEditFeatureTests

@MainActor
@Suite("ChecklistEditReducer")
struct ChecklistEditFeatureTests {
  // MARK: Internal

  @Test("adding inserts an empty item at the top, then editing renames it")
  func addNewItem() async {
    let store = TestStore(initialState: ChecklistEditReducer.State(items: items)) {
      ChecklistEditReducer(dataManager: MockChecklistDataManager())
    } withDependencies: {
      $0.uuid = .constant(UUID(100))
    }

    await store.send(.addItem) {
      $0.items.insert(ChecklistItem(name: "", id: UUID(100)), at: 0)
    }
    await store.send(.itemDidChange(index: 0, text: "New")) {
      $0.items[0].name = "New"
    }
  }

  @Test("load replaces the items with the stored list")
  func loadItems() async {
    let store = TestStore(initialState: ChecklistEditReducer.State(items: [])) {
      ChecklistEditReducer(dataManager: MockChecklistDataManager(items: items))
    }

    await store.send(.load) {
      $0.items = items
    }
  }

  @Test("save hands the current items to the data manager")
  func saveItems() async {
    let dataManager = MockChecklistDataManager()
    let store = TestStore(initialState: ChecklistEditReducer.State(items: items)) {
      ChecklistEditReducer(dataManager: dataManager)
    }

    await store.send(.save)

    #expect(dataManager.items == items)
  }

  // MARK: Private

  private let items = [
    ChecklistItem(name: "First", id: UUID(0)),
    ChecklistItem(name: "Second", id: UUID(1)),
    ChecklistItem(name: "Third", id: UUID(2)),
  ]
}
