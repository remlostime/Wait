//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import DesignSystem
import Domain
import SwiftUI

// MARK: - ChecklistView

public struct ChecklistView: View {
  // MARK: Lifecycle

  public init(store: StoreOf<ChecklistFeature>) {
    self.store = store
  }

  // MARK: Public

  public var body: some View {
    List {
      Section {
        ForEach(store.item.checklist) { entry in
          Button {
            store.send(.toggled(entry.id))
          } label: {
            HStack(spacing: Spacing.m) {
              Image(systemName: entry.isChecked ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(entry.isChecked ? Palette.accent : .secondary)
                .imageScale(.large)
              Text(entry.name)
                .foregroundStyle(entry.isChecked ? .secondary : .primary)
                .strikethrough(entry.isChecked)
                .multilineTextAlignment(.leading)
            }
          }
          .accessibilityAddTraits(entry.isChecked ? .isSelected : [])
        }
      } header: {
        Text(store.title)
      }
    }
    .navigationTitle("\(store.item.symbol) Checklist")
    .toolbar {
      Button("Reset") {
        store.send(.resetTapped)
      }
      .disabled(store.item.checkedCount == 0)
    }
  }

  // MARK: Private

  private let store: StoreOf<ChecklistFeature>
}
