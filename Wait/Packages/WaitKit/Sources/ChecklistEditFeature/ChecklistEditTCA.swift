//
// Created by: kai_chen on 10/9/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Foundation
import Model

// MARK: - ChecklistEditReducer

/// Edits the checklist template. The data manager is injected; ids come from `@Dependency(\.uuid)`.
@Reducer
public struct ChecklistEditReducer {
  // MARK: Lifecycle

  public init(dataManager: ChecklistDataManager) {
    self.dataManager = dataManager
  }

  // MARK: Public

  @ObservableState
  public struct State: Equatable {
    // MARK: Lifecycle

    public init(items: [ChecklistItem]) {
      self.items = items
    }

    // MARK: Public

    public var items: [ChecklistItem]
  }

  public enum Action: Equatable {
    case addItem
    case save
    case load
    case itemDidChange(index: Int, text: String)
  }

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
        case .addItem:
          state.items.insert(ChecklistItem(name: "", id: uuid()), at: 0)
          return .none
        case .load:
          if let checklistItems = dataManager.load() {
            state.items = checklistItems
          }
          return .none
        case .save:
          dataManager.save(items: state.items)
          return .none
        case let .itemDidChange(index, text):
          state.items[index].name = text
          return .none
      }
    }
  }

  // MARK: Private

  @Dependency(\.uuid) private var uuid

  private let dataManager: ChecklistDataManager
}
