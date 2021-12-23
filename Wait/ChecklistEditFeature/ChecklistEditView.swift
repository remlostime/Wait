//
// Created by: kai_chen on 10/9/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Model
import SwiftUI

// MARK: - ChecklistEditView

public struct ChecklistEditView: View {
  let store: Store<ChecklistEditState, ChecklistEditAction>

  public init(store: Store<ChecklistEditState, ChecklistEditAction>) {
    self.store = store
  }

  public var body: some View {
    WithViewStore(self.store) { viewStore in
      List {
        ForEach(Array(viewStore.items.enumerated()), id: \.element.id) { index, _ in
          TextField(
            "New Item",
            text: viewStore.binding(
              get: { $0.items[index].name },
              send: { .itemDidChange(index: index, text: $0) }
            )
          )
        }
      }
      .navigationBarItems(
        trailing:
        HStack {
          Button("Save") {
            viewStore.send(.save)
          }
          Button(action: { viewStore.send(.addItem) }) {
            Image(systemName: "plus")
          }
        }
      )
      .onDisappear {
        viewStore.send(.save)
      }
    }
  }
}

// MARK: - ChecklistEditView_Previews

struct ChecklistEditView_Previews: PreviewProvider {
  static var previews: some View {
    ChecklistEditView(store: Store(
      initialState: ChecklistEditState(items: []),
      reducer: ChecklistEditReducerBuilder.build(),
      environment: ChecklistEditEnvironment()
    ))
  }
}