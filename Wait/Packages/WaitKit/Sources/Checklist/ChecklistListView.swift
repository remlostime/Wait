//
// Created by: kai_chen on 12/16/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Model
import SwiftUI

// MARK: - ChecklistListView

public struct ChecklistListView: View {
  // MARK: Lifecycle

  public init(store: StoreOf<ChecklistListReducer>) {
    self.store = store
  }

  // MARK: Public

  public var body: some View {
    List(store.checklistItems) { item in
      Checklist(item: item) { tapped in
        guard let index = store.checklistItems.firstIndex(of: tapped) else {
          return
        }
        store.send(tapped.isChecked ? .uncheck(index: index) : .check(index: index))
      }
    }
    .navigationTitle(navigationTitle(with: store.checklistItems))
  }

  // MARK: Private

  private let store: StoreOf<ChecklistListReducer>

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
    ChecklistListView(
      store: Store(
        initialState: ChecklistListReducer.State(checklistItems: [
          ChecklistItem(name: "First", id: UUID()),
          ChecklistItem(name: "Second", id: UUID()),
          ChecklistItem(name: "Third", id: UUID()),
        ])
      ) {
        ChecklistListReducer(save: { _ in })
      }
    )
  }
}
