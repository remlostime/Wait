//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Domain
import Foundation
import Persistence

// MARK: - ChecklistFeature

/// The per-stock checklist. It mutates the shared `WatchlistItem`, so the list and details screens update too.
@Reducer
public struct ChecklistFeature {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  @ObservableState
  public struct State: Equatable, Identifiable {
    // MARK: Lifecycle

    public init(item: Shared<WatchlistItem>) {
      _item = item
    }

    // MARK: Public

    @Shared public var item: WatchlistItem

    public var id: String {
      item.symbol
    }

    public var title: String {
      let total = item.checklist.count
      let done = item.checkedCount
      return total > 0 && done == total ? "All Done" : "\(done) / \(total)"
    }
  }

  public enum Action: Equatable {
    case toggled(ChecklistItem.ID)
    case resetTapped
  }

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
        case let .toggled(id):
          guard state.item.checklist.contains(where: { $0.id == id }) else {
            return .none
          }
          state.$item.update(now: now) { item in
            if let index = item.checklist.firstIndex(where: { $0.id == id }) {
              item.checklist[index].isChecked.toggle()
            }
          }
          return .none

        case .resetTapped:
          state.$item.update(now: now) { item in
            for index in item.checklist.indices {
              item.checklist[index].isChecked = false
            }
          }
          return .none
      }
    }
  }

  // MARK: Private

  @Dependency(\.date.now) private var now
}
