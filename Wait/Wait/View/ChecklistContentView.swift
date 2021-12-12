//
// Created by: kai_chen on 12/7/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Model
import Size
import SwiftUI

// MARK: - ChecklistContentView

struct ChecklistContentView: View {
  // MARK: Lifecycle

  init(checklistItems: Binding<[ChecklistItem]>) {
    _checklistItems = checklistItems
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

  var body: some View {
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
            if currentChecklistItemIndex > 0 {
              Button(action: { currentChecklistItemIndex -= 1 }) {
                Image(systemName: "arrow.uturn.backward")
              }
            }

            Button(action: { currentChecklistItemIndex = 0 }) {
              Image(systemName: "gobackward")
            }
          }
        case .list:
          List {
            ForEach(checklistItems.indices) { index in
              Checklist(item: $checklistItems[index])
            }
          }
          .listStyle(.plain)
      }
    }
    .navigationTitle(progress)
  }

  // MARK: Private

  @State private var currentChecklistItemIndex: Int = 0
  @ObservedObject private var viewModel = ChecklistViewModel()

  @State private var cardTranslation: CGSize = .zero

  private var translation: Double { Double(cardTranslation.width / bounds.width) }
  private var bounds: CGRect { UIScreen.main.bounds }

  private var progress: String {
    "\(currentChecklistItemIndex + 1) / \(checklistItems.count)"
  }

  private var rotationAngle: Angle {
    Angle(degrees: 75 * translation)
  }

  private var isLightMode: Bool {
    colorScheme == .light
  }

  private var checklistCardView: some View {
    ChecklistCardView(checklistItem: $checklistItems[currentChecklistItemIndex], didTap: didTap)
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
    let isChecked = viewModel.isChecked

    checklistItems[currentChecklistItemIndex].isChecked = isChecked
    currentChecklistItemIndex = (currentChecklistItemIndex + 1) % checklistItems.count

    if isChecked {
      let translation = change.translation
      let offset = (isChecked ? 2 : -2) * bounds.width
      cardTranslation = CGSize(width: translation.width + offset,
                               height: translation.height)

      reset()
    } else {
      cardTranslation = .zero
      viewModel.reset()
    }
  }

  private func didTap(isChecked: Bool) {
    checklistItems[currentChecklistItemIndex].isChecked = isChecked
    currentChecklistItemIndex = (currentChecklistItemIndex + 1) % checklistItems.count
  }
}

// MARK: - ChecklistContentView_Previews

struct ChecklistContentView_Previews: PreviewProvider {
  static var previews: some View {
    ChecklistContentView(checklistItems: .constant(ChecklistItem.allItems))
  }
}
