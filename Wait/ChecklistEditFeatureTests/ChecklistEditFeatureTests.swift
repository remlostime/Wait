//
// Created by: kai_chen on 12/23/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Model
import XCTest
@testable import ChecklistEditFeature

// MARK: - UUIDGenerator

private class UUIDGenerator {
  // MARK: Lifecycle

  init(uuid: UUID) {
    self.uuid = uuid
  }

  // MARK: Internal

  var uuid: UUID

  func callAsFunction() -> UUID {
    uuid
  }
}

// MARK: - ChecklistEditFeatureTests

class ChecklistEditFeatureTests: XCTestCase {
  func testAddNewItem() {
    let state = ChecklistEditState(items: [
      ChecklistItem(name: "First", id: UUID()),
      ChecklistItem(name: "Second", id: UUID()),
      ChecklistItem(name: "Third", id: UUID()),
    ])

    let uuidGenerator = UUIDGenerator(uuid: UUID())

    let store = TestStore(
      initialState: state,
      reducer: ChecklistEditReducerBuilder.build(),
      environment: ChecklistEditEnvironment(checklistDataManager: MockChecklistDataManager(), uuid: { uuidGenerator() })
    )

    store.send(.addItem) {
      $0.items.insert(ChecklistItem(name: "", id: uuidGenerator.uuid), at: 0)
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
      ChecklistItem(name: "First", id: UUID()),
      ChecklistItem(name: "Second", id: UUID()),
      ChecklistItem(name: "Third", id: UUID()),
    ]

    let uuidGenerator = UUIDGenerator(uuid: UUID())

    let store = TestStore(
      initialState: .init(items: []),
      reducer: ChecklistEditReducerBuilder.build(),
      environment: ChecklistEditEnvironment(checklistDataManager: MockChecklistDataManager(items: items), uuid: { uuidGenerator() })
    )

    store.send(.load) {
      $0.items = items
    }
  }

  func testSaveItems() {
    let items = [
      ChecklistItem(name: "First", id: UUID()),
      ChecklistItem(name: "Second", id: UUID()),
      ChecklistItem(name: "Third", id: UUID()),
    ]

    let dataManager = MockChecklistDataManager()
    let uuidGenerator = UUIDGenerator(uuid: UUID())
    let store = TestStore(
      initialState: .init(items: items),
      reducer: ChecklistEditReducerBuilder.build(),
      environment: ChecklistEditEnvironment(checklistDataManager: dataManager, uuid: { uuidGenerator() })
    )

    store.send(.save) { _ in }

    XCTAssertEqual(items, dataManager.items)
  }
}
