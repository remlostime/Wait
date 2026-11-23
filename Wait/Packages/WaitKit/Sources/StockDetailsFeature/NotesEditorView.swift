//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import SwiftUI

// MARK: - NotesEditorView

public struct NotesEditorView: View {
  // MARK: Lifecycle

  public init(store: StoreOf<NotesEditorFeature>) {
    self.store = store
  }

  // MARK: Public

  public var body: some View {
    Form {
      TextField("Write some notes…", text: $store.text, axis: .vertical)
        .lineLimit(6...)
    }
    .navigationTitle("Notes")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { store.send(.cancelTapped) }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") { store.send(.saveTapped) }
      }
    }
  }

  // MARK: Private

  @Bindable private var store: StoreOf<NotesEditorFeature>
}
