//
// Created by: kai_chen on 12/16/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Model
import Size
import SwiftUI

struct ChecklistListView: View {
  let store: Store<ChecklistListState, ChecklistListAction>

  var body: some View {
    WithViewStore(store) { viewStore in
      List {
        ForEach(0..<viewStore.checklistItems.count) { index in
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

struct ChecklistListView_Previews: PreviewProvider {
  static var previews: some View {
    ChecklistListView(store: Store<ChecklistListState, ChecklistListAction>.init(
      initialState: ChecklistListState(
        checklistItems: [
          ChecklistItem(name: "First"),
          ChecklistItem(name: "Second"),
          ChecklistItem(name: "Third")]),
      reducer: ChecklistListReducerBuilder.build(),
      environment: ChecklistListEnvironment()))
  }
}
