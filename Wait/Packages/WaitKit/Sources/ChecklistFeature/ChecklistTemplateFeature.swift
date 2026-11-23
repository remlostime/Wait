//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Domain
import Foundation
import Persistence

// MARK: - ChecklistTemplateFeature

/// Edits the template that seeds each newly added stock's checklist. It replaces the legacy `ChecklistEditFeature`.
@Reducer
public struct ChecklistTemplateFeature {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  @ObservableState
  public struct State: Equatable {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    @Shared(.checklistTemplate) public var items
  }

  public enum Action: Equatable {
    case addTapped
    case nameChanged(ChecklistItem.ID, String)
    case deleted(IndexSet)
    case moved(IndexSet, Int)
    case onDisappear
  }

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
        case .addTapped:
          let item = ChecklistItem(id: uuid(), name: "")
          state.$items.withLock { _ = $0.insert(item, at: 0) }
          return .none

        case let .nameChanged(id, name):
          state.$items.withLock { $0[id: id]?.name = name }
          return .none

        case let .deleted(offsets):
          state.$items.withLock { $0.remove(atOffsets: offsets) }
          return .none

        case let .moved(source, destination):
          state.$items.withLock { $0.move(fromOffsets: source, toOffset: destination) }
          return .none

        case .onDisappear:
          state.$items.withLock { items in
            items.removeAll { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
          }
          return .none
      }
    }
  }

  // MARK: Private

  @Dependency(\.uuid) private var uuid
}
