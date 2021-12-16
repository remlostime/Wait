//
// Created by: kai_chen on 12/7/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Model
import Size
import SwiftUI

// MARK: - ChecklistContentView

public struct ChecklistContentView: View {
  // MARK: Lifecycle

  public init(store: Store<ChecklistRootState, ChecklistRootAction>, checklistItems: Binding<[ChecklistItem]>) {
    self.store = store
    _checklistItems = checklistItems
  }

  // MARK: Public

  public var body: some View {
    WithViewStore(checklistStore) { viewStore in
      VStack {
        HStack {
          Spacer()
          Picker("Checklist Style", selection: $style) {
            Text("Card").tag(ChecklistStyle.card)
            Text("List").tag(ChecklistStyle.list)
          }
        }
        .padding()

        switch style {
          case .card:
            checklistCardView
            Spacer()
              .frame(height: Size.verticalPadding16)
            HStack(spacing: Size.horizontalPadding8) {
              Button(action: { viewStore.send(.goBack) }) {
                Image(systemName: "arrow.uturn.backward")
              }

              Button(action: { viewStore.send(.startOver) }) {
                Image(systemName: "gobackward")
              }
            }
          case .list:
            Text("haha")
        }
      }
      .navigationTitle(viewStore.progress)
//      .onChange(of: viewStore.state.checklistItems, perform: { newValue in
//        checklistItems = newValue
//      })
    }
  }

  // MARK: Internal

  enum ChecklistStyle {
    case card
    case list
  }

  enum ChecklistFilter {
    case all
    case checked
    case unchecked
  }

  @Binding var checklistItems: [ChecklistItem]

  @Environment(\.colorScheme) var colorScheme

  @State var style: ChecklistStyle = .card

  @State var filter: ChecklistFilter = .unchecked

  // MARK: Private

  private let store: Store<ChecklistRootState, ChecklistRootAction>

  @ObservedObject private var viewModel = ChecklistViewModel()

  @State private var cardTranslation: CGSize = .zero

  private var checklistStore: Store<ChecklistState, ChecklistAction> {
    store.scope(
      state: \.rootState,
      action: ChecklistRootAction.rootAction
    )
  }

  private var checklistCardStore: Store<ChecklistCardState, ChecklistCardAction> {
    store.scope(
      state: \.cardState,
      action: ChecklistRootAction.cardAction
    )
  }

  private var translation: Double { Double(cardTranslation.width / bounds.width) }
  private var bounds: CGRect { UIScreen.main.bounds }

  private var rotationAngle: Angle {
    Angle(degrees: 75 * translation)
  }

  private var isLightMode: Bool {
    colorScheme == .light
  }

  private var checklistCardView: some View {
    ChecklistCardView(store: checklistCardStore)
      .background(isLightMode ? Color.white : Color.gray)
      .cornerRadius(20)
      .shadow(radius: 10)
      .rotationEffect(rotationAngle)
      .offset(x: cardTranslation.width, y: cardTranslation.height)
      .animation(.spring(response: 0.5, dampingFraction: 0.4, blendDuration: 2))
      .gesture(
        DragGesture()
          .onChanged { change in
            self.cardTranslation = change.translation
          }
          .onEnded { change in
            self.updateDecisionStateForChange(change)
            self.handle(change)
          }
      )
  }

  private func updateDecisionStateForChange(_ change: DragGesture.Value) {
    viewModel.updateDecisionStateForTranslation(
      translation,
      andPredictedEndLocationX: change.predictedEndLocation.x,
      inBounds: bounds
    )
  }

  private func reset() {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//      self.showFetchingJoke = true
//      self.hudOpacity = 0.5
      self.cardTranslation = .zero

      self.viewModel.reset()
//      self.viewModel.fetchJoke()

//      DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
//        self.showFetchingJoke = false
//        self.showJokeView = true
//        self.hudOpacity = 0
//      }
    }
  }

  private func handle(_ change: DragGesture.Value) {
//    let isChecked = viewModel.isChecked
//
//    checklistItems[currentChecklistItemIndex].isChecked = isChecked
//    currentChecklistItemIndex = (currentChecklistItemIndex + 1) % checklistItems.count
//
//    if isChecked {
//      let translation = change.translation
//      let offset = (isChecked ? 2 : -2) * bounds.width
//      cardTranslation = CGSize(width: translation.width + offset,
//                               height: translation.height)
//
//      reset()
//    } else {
//      cardTranslation = .zero
//      viewModel.reset()
//    }
  }
}

// MARK: - ChecklistContentView_Previews

struct ChecklistContentView_Previews: PreviewProvider {
  static var previews: some View {
    ChecklistContentView(
      store: Store<ChecklistRootState, ChecklistRootAction>(
        initialState: ChecklistRootState(
          rootState: ChecklistState(checklistItems: [
            ChecklistItem(name: "This is first"),
            ChecklistItem(name: "This is second"),
            ChecklistItem(name: "This is third"),
          ])),
        reducer: ChecklistRootReducerBuilder.build(),
        environment: ChecklistRootEnvironment()
      ),
      checklistItems: .constant([ChecklistItem(name: "haha")])
    )
  }
}
