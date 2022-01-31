//
// Created by: kai_chen on 12/16/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Model
import Size
import SwiftUI

// MARK: - ChecklistListView

struct ChecklistListView: View {
  let store: Store<ChecklistListState, ChecklistListAction>

  var body: some View {
    WithViewStore(store) { viewStore in
      List {
        ForEach(0 ..< viewStore.checklistItems.count) { index in
          Checklist(item: viewStore.checklistItems[index]) { item in
            if item.isChecked {
              viewStore.send(.uncheck(index: index))
            } else {
              viewStore.send(.check(index: index))
            }
          }
        }
      }
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
