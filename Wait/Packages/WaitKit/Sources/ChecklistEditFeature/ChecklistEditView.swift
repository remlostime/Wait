//
// Created by: kai_chen on 10/9/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Model
import SwiftUI

// MARK: - ChecklistEditView

public struct ChecklistEditView: View {
  // MARK: Lifecycle

  public init(store: StoreOf<ChecklistEditReducer>) {
    self.store = store
  }

  // MARK: Public

  public var body: some View {
    List {
      ForEach(Array(store.items.enumerated()), id: \.element.id) { index, _ in
        TextField(
          "New Item",
          text: Binding(
            get: { store.items[index].name },
            set: { store.send(.itemDidChange(index: index, text: $0)) }
          )
        )
      }
    }
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button("Save") {
          store.send(.save)
        }
        Button(action: { store.send(.addItem) }) {
          Image(systemName: "plus")
        }
      }
    }
    .onDisappear {
      store.send(.save)
    }
    .onAppear {
      store.send(.load)
    }
  }

  // MARK: Internal

  @Bindable var store: StoreOf<ChecklistEditReducer>
}

// MARK: - ChecklistEditView_Previews

struct ChecklistEditView_Previews: PreviewProvider {
  static var previews: some View {
    ChecklistEditView(
      store: Store(
        initialState: ChecklistEditReducer.State(items: [
          ChecklistItem(name: "First", id: UUID()),
          ChecklistItem(name: "Second", id: UUID()),
        ])
      ) {
        ChecklistEditReducer(dataManager: DefaultChecklistDataManager())
      }
    )
  }
}
