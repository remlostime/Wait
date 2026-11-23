//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import DesignSystem
import Domain
import StockDetailsFeature
import SwiftUI

// MARK: - AddStockView

public struct AddStockView: View {
  // MARK: Lifecycle

  public init(store: StoreOf<AddStockFeature>) {
    self.store = store
  }

  // MARK: Public

  public var body: some View {
    NavigationStack {
      List {
        if let message = store.errorMessage {
          Section {
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
          }
        }
        ForEach(store.results) { result in
          Button {
            store.send(.resultTapped(result))
          } label: {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
              Text(result.symbol).font(.headline)
              Text(result.name).font(.subheadline).foregroundStyle(.secondary)
              if let exchange = result.exchange {
                Text(exchange).font(.caption).foregroundStyle(.tertiary)
              }
            }
            .foregroundStyle(.primary)
          }
        }
      }
      .overlay {
        if store.isSearching, store.results.isEmpty {
          ProgressView()
        } else if !store.query.isEmpty, !store.isSearching, store.results.isEmpty, store.errorMessage == nil {
          ContentUnavailableView.search(text: store.query)
        }
      }
      .searchable(text: $store.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Symbol or company")
      .autocorrectionDisabled()
      .textInputAutocapitalization(.characters)
      .navigationTitle("Add Stock")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { store.send(.cancelTapped) }
        }
      }
      .navigationDestination(item: $store.scope(\.$destination, action: \.destination).ladderEditor) { editor in
        LadderEditorView(store: editor)
      }
    }
  }

  // MARK: Private

  @Bindable private var store: StoreOf<AddStockFeature>
}
