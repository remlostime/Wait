//
// Created by: kai_chen on 12/6/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Model
import Size
import SwiftUI

// MARK: - ChecklistCardView

struct ChecklistCardView: View {
  // MARK: Internal

  let store: Store<ChecklistCardState, ChecklistCardAction>

  var body: some View {
    WithViewStore(store) { viewStore in
      ZStack {
        VStack(alignment: .center, spacing: 20) {
          Text(viewStore.state.checklistItem.name)
            .font(.largeTitle)
            .minimumScaleFactor(0.2)
            .allowsTightening(true)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .animation(.easeInOut)
          HStack(spacing: Size.horizontalPadding32) {
            Button(action: { viewStore.send(.uncheck) }) {
              Image(systemName: "multiply")
            }
            Button(action: { viewStore.send(.check) }) {
              Image(systemName: "checkmark")
            }
          }
          Image(systemName: viewStore.state.checklistItem.isChecked ? "checkmark.circle.fill" : "checkmark.circle")
        }
        .frame(width: min(300, bounds.width * 0.7), height: min(400, bounds.height * 0.6))
        .padding(20)
        .cornerRadius(20)
      }
    }
  }

  // MARK: Private

  private var bounds: CGRect { UIScreen.main.bounds }
}

// MARK: - ChecklistCardView_Previews

struct ChecklistCardView_Previews: PreviewProvider {
  static var previews: some View {
    let store = Store<ChecklistCardState, ChecklistCardAction>.init(
      initialState: ChecklistCardState(checklistItem: ChecklistItem(name: "test", id: UUID()), currentChecklistItemIndex: 0),
      reducer: ChecklistCardReducerBuilder.build(),
      environment: ChecklistCardEnvironment()
    )
    return ChecklistCardView(store: store)
      .previewLayout(.sizeThatFits)
  }
}
