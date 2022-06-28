//
// Created by: kai_chen on 12/16/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Model
import Size
import SwiftUI

// MARK: - ChecklistListView

public struct ChecklistListView: View {
  // MARK: Lifecycle

  public init(store: Store<ChecklistListState, ChecklistListAction>) {
    self.store = store
  }

  // MARK: Public

  public var body: some View {
    WithViewStore(store) { viewStore in
      List(viewStore.checklistItems) { item in
        Checklist(item: item) { item in
          if item.isChecked {
            viewStore.send(.uncheck(index: viewStore.checklistItems.firstIndex(of: item)!))
          } else {
            viewStore.send(.check(index: viewStore.checklistItems.firstIndex(of: item)!))
          }
        }
      }
      .navigationTitle(navigationTitle(with: viewStore.checklistItems))
    }
  }

  // MARK: Private

  private let store: Store<ChecklistListState, ChecklistListAction>

  private func navigationTitle(with checklistItems: [ChecklistItem]) -> String {
    let itemCheckedCount = checklistItems.reduce(into: 0) { count, item in
      count += item.isChecked ? 1 : 0
    }

    if itemCheckedCount == checklistItems.count {
      return "All Done"
    } else {
      return "\(itemCheckedCount) / \(checklistItems.count)"
    }
  }
}

// MARK: - ChecklistListView_Previews

struct ChecklistListView_Previews: PreviewProvider {
  static var previews: some View {
    ChecklistListView(store: Store<ChecklistListState, ChecklistListAction>.init(
      initialState: ChecklistListState(
        checklistItems: [
          ChecklistItem(name: "First", id: UUID()),
          ChecklistItem(name: "Second", id: UUID()),
          ChecklistItem(name: "Third", id: UUID()),
        ]),
      reducer: ChecklistListReducerBuilder.build(),
      environment: ChecklistListEnvironment()
    ))
  }
}
