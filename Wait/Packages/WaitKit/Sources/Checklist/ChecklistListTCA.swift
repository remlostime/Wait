//
// Created by: kai_chen on 12/16/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Foundation
import Model

// MARK: - ChecklistListReducer

/// Checks and unchecks a stock's checklist and persists every change.
/// Persistence is injected (`save`) so tests never write to disk.
@Reducer
public struct ChecklistListReducer {
  // MARK: Lifecycle

  public init(save: @escaping ([ChecklistItem]) -> Void) {
    self.save = save
  }

  public init(storage: ChecklistStorage) {
    self.init(save: { storage.save(checklistItems: $0) })
  }

  // MARK: Public

  @ObservableState
  public struct State: Equatable {
    // MARK: Lifecycle

    public init(checklistItems: [ChecklistItem]) {
      self.checklistItems = checklistItems
    }

    // MARK: Public

    public var checklistItems: [ChecklistItem]
  }

  public enum Action: Equatable {
    case check(index: Int)
    case uncheck(index: Int)
  }

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
        case let .check(index):
          state.checklistItems[index].isChecked = true
        case let .uncheck(index):
          state.checklistItems[index].isChecked = false
      }
      save(state.checklistItems)
      return .none
    }
  }

  // MARK: Private

  private let save: ([ChecklistItem]) -> Void
}
