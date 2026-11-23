//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ChecklistFeature
import ComposableArchitecture
import DependenciesTestSupport
import Domain
import Foundation
import Persistence
import Testing

let now = Date(timeIntervalSince1970: 1_795_186_800)

func checklistItem() -> WatchlistItem {
  WatchlistItem(
    symbol: "AAPL",
    name: "Apple",
    checklist: [ChecklistItem(id: UUID(0), name: "A"), ChecklistItem(id: UUID(1), name: "B")],
    createdAt: .distantPast,
    updatedAt: .distantPast
  )
}

@MainActor
@Suite(.dependencies { $0.defaultFileStorage = .inMemory })
struct ChecklistFeatureTests {
  @Test func toggleStampsAndUpdatesTheTitle() async {
    let store = TestStore(initialState: ChecklistFeature.State(item: Shared(value: checklistItem()))) {
      ChecklistFeature()
    } withDependencies: {
      $0.date.now = now
    }
    #expect(store.state.title == "0 / 2")
    await store.send(.toggled(UUID(0))) {
      $0.$item.withLock {
        $0.checklist[0].isChecked = true
        $0.updatedAt = now
      }
    }
    #expect(store.state.title == "1 / 2")
    await store.send(.toggled(UUID(1))) {
      $0.$item.withLock { $0.checklist[1].isChecked = true }
    }
    #expect(store.state.title == "All Done")
  }

  @Test func unknownItemIsIgnored() async {
    let store = TestStore(initialState: ChecklistFeature.State(item: Shared(value: checklistItem()))) {
      ChecklistFeature()
    } withDependencies: {
      $0.date.now = now
    }
    await store.send(.toggled(UUID(9)))
  }

  @Test func resetUnchecksEverything() async {
    var item = checklistItem()
    item.checklist[0].isChecked = true
    let store = TestStore(initialState: ChecklistFeature.State(item: Shared(value: item))) {
      ChecklistFeature()
    } withDependencies: {
      $0.date.now = now
    }
    await store.send(.resetTapped) {
      $0.$item.withLock {
        $0.checklist[0].isChecked = false
        $0.updatedAt = now
      }
    }
  }

  @Test func templateAddRenameAndPrune() async {
    @Shared(.checklistTemplate) var template
    $template.withLock { $0 = [] }
    let store = TestStore(initialState: ChecklistTemplateFeature.State()) {
      ChecklistTemplateFeature()
    } withDependencies: {
      $0.uuid = .incrementing
    }
    await store.send(.addTapped) {
      $0.$items.withLock { _ = $0.insert(ChecklistItem(id: UUID(0), name: ""), at: 0) }
    }
    await store.send(.addTapped) {
      $0.$items.withLock { _ = $0.insert(ChecklistItem(id: UUID(1), name: ""), at: 0) }
    }
    await store.send(.nameChanged(UUID(0), "Wait 30 minutes")) {
      $0.$items.withLock { $0[id: UUID(0)]?.name = "Wait 30 minutes" }
    }
    await store.send(.onDisappear) {
      $0.$items.withLock { _ = $0.remove(id: UUID(1)) }
    }
  }
}
