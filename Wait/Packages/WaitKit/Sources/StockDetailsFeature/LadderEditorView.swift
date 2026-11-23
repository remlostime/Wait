//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import DesignSystem
import Domain
import SwiftUI

// MARK: - LadderEditorView

public struct LadderEditorView: View {
  // MARK: Lifecycle

  public init(store: StoreOf<LadderEditorFeature>) {
    self.store = store
  }

  // MARK: Public

  public var body: some View {
    Form {
      if let price = store.currentPrice {
        Section {
          LabeledContent("Current price") {
            Text(price, format: .currency(code: "USD"))
          }
        }
      }
      Section {
        row(.buyLow, text: $store.buyLow)
        row(.buyHigh, text: $store.buyHigh)
        row(.fair, text: $store.fair)
        row(.trim, text: $store.trim)
        row(.sell, text: $store.sell)
      } header: {
        Text("Price ladder")
      } footer: {
        footer
      }
    }
    .navigationTitle(store.symbol)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { store.send(.cancelTapped) }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") { store.send(.saveTapped) }
          .disabled(!store.canSave)
      }
    }
  }

  // MARK: Private

  @Bindable private var store: StoreOf<LadderEditorFeature>

  @ViewBuilder private var footer: some View {
    switch store.parsed {
      case let .success(ladder) where ladder.isEmpty:
        Text("All fields are empty. Saving clears this stock's targets.")
      case .success:
        if let hint = store.derivedFairHint {
          Text("Fair is derived as buy high ÷ 0.7 = \(hint.formatted(.currency(code: "USD"))).")
        } else {
          Text("Each price must be at least the one above it. Leave a field empty to skip it.")
        }
      case let .failure(error):
        Text(error.message).foregroundStyle(Palette.stockDown)
    }
  }

  private func row(_ rung: PriceLadder.Rung, text: Binding<String>) -> some View {
    LabeledContent(rung.title) {
      HStack(spacing: Spacing.xxs) {
        Text("$").foregroundStyle(.secondary)
        TextField("—", text: text)
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
          .accessibilityLabel(rung.title)
      }
    }
  }
}

#Preview {
  let ladder = (try? PriceLadder(buyHigh: Decimal(string: "175"))) ?? .empty
  NavigationStack {
    LadderEditorView(store: Store(initialState: LadderEditorFeature.State(symbol: "AAPL", ladder: ladder, currentPrice: Decimal(string: "189.98"))) {
      LadderEditorFeature()
    })
  }
}
