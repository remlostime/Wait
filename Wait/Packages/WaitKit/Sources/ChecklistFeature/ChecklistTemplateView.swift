//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import DesignSystem
import Domain
import SwiftUI

// MARK: - ChecklistTemplateView

public struct ChecklistTemplateView: View {
  // MARK: Lifecycle

  public init(store: StoreOf<ChecklistTemplateFeature>) {
    self.store = store
  }

  // MARK: Public

  public var body: some View {
    List {
      Section {
        ForEach(store.items) { item in
          TextField(
            "Prompt",
            text: Binding(get: { item.name }, set: { store.send(.nameChanged(item.id, $0)) }),
            axis: .vertical
          )
        }
        .onDelete { store.send(.deleted($0)) }
        .onMove { store.send(.moved($0, $1)) }
      } footer: {
        Text("New stocks start with these prompts. Empty prompts are removed when you leave this screen.")
      }
    }
    .navigationTitle("Checklist Template")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) { EditButton() }
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          store.send(.addTapped)
        } label: {
          Label("Add prompt", systemImage: "plus")
        }
      }
    }
    .onDisappear { store.send(.onDisappear) }
  }

  // MARK: Private

  private let store: StoreOf<ChecklistTemplateFeature>
}

#Preview {
  NavigationStack {
    ChecklistTemplateView(store: Store(initialState: ChecklistTemplateFeature.State()) { ChecklistTemplateFeature() })
  }
}
