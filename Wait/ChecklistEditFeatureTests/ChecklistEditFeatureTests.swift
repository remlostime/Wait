//
// Created by: kai_chen on 12/23/21.
// Copyright © 2021 Wait. All rights reserved.
//

import XCTest
import ComposableArchitecture
import Model
@testable import ChecklistEditFeature

class MockChecklistDataManager: ChecklistDataManager {
  var items: [ChecklistItem] = []

  init(items: [ChecklistItem] = []) {
    self.items = items
  }

  func save(items: [ChecklistItem]) {
    self.items = items
  }

  func load() -> [ChecklistItem]? {
    return items
  }
}

class ChecklistEditFeatureTests: XCTestCase {

  func testAddNewItem() {
    let state = ChecklistEditState(items: [
      ChecklistItem(name: "First"),
      ChecklistItem(name: "Second"),
      ChecklistItem(name: "Third")
    ])
    let store = TestStore(
      initialState: state,
      reducer: ChecklistEditReducerBuilder.build(),
      environment: ChecklistEditEnvironment(checklistDataManager: MockChecklistDataManager()))

    store.send(.addItem) {
      $0.items.insert(ChecklistItem(name: ""), at: 0)
    }

    store.send(.itemDidChange(index: 0, text: "New")) {
      guard var firstItem = $0.items.first else {
        XCTFail("Item is empty")
        return
      }

      firstItem.name = "New"
      $0.items[0] = firstItem
    }
  }

  func testLoadItems() {
    let items = [
      ChecklistItem(name: "First"),
      ChecklistItem(name: "Second"),
      ChecklistItem(name: "Third")
    ]

    let store = TestStore(
      initialState: .init(items: []),
      reducer: ChecklistEditReducerBuilder.build(),
      environment: ChecklistEditEnvironment(checklistDataManager: MockChecklistDataManager(items: items)))

    store.send(.load) {
      $0.items = items
    }
  }

  func testSaveItems() {
    let items = [
      ChecklistItem(name: "First"),
      ChecklistItem(name: "Second"),
      ChecklistItem(name: "Third")
    ]

    let dataManager = MockChecklistDataManager()
    let store = TestStore(
      initialState: .init(items: items),
      reducer: ChecklistEditReducerBuilder.build(),
      environment: ChecklistEditEnvironment(checklistDataManager: dataManager))

    store.send(.save) { _ in }

    XCTAssertEqual(items, dataManager.items)
  }

}
