//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ChecklistFeature
import ComposableArchitecture
import DesignSystem
import Domain
import Persistence
import StockDetailsFeature
import SwiftUI

// MARK: - WatchlistView

public struct WatchlistView: View {
  // MARK: Lifecycle

  public init(store: StoreOf<WatchlistFeature>) {
    self.store = store
  }

  // MARK: Public

  public var body: some View {
    NavigationStack(path: $store.scope(\.path, action: \.path)) {
      list
        .navigationTitle("Wait")
        .toolbar {
          ToolbarItem(placement: .topBarLeading) { EditButton() }
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              store.send(.addTapped)
            } label: {
              Label("Add stock", systemImage: "plus")
            }
          }
        }
        .sheet(item: $store.scope(\.$destination, action: \.destination).addStock) { addStore in
          AddStockView(store: addStore)
        }
        // Shares the `.all` cancel ID with scene-active and pull-to-refresh; coalescing makes repeated loads cheap.
        .task { await store.send(.task).finish() }
    } destination: { store in
      switch store.case {
        case let .details(detailsStore):
          StockDetailsView(store: detailsStore)
        case let .checklist(checklistStore):
          ChecklistView(store: checklistStore)
      }
    }
  }

  // MARK: Private

  @Bindable private var store: StoreOf<WatchlistFeature>

  private var list: some View {
    List {
      if case let .delayed(message) = store.quotesStatus {
        Section {
          Label(message, systemImage: "clock.badge.exclamationmark").font(.footnote).foregroundStyle(.secondary)
        }
      }
      if !store.favorites.isEmpty {
        Section("Favorites") { rows(store.favorites, section: .favorites) }
      }
      if !store.others.isEmpty {
        Section("Watchlist") { rows(store.others, section: .others) }
      }
    }
    .listStyle(.insetGrouped)
    .refreshable { await store.send(.refreshPulled).finish() }
    .overlay {
      if store.items.isEmpty {
        ContentUnavailableView {
          Label("No stocks yet", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
          Text("Add a stock and set the price you'd be happy to buy at.")
        } actions: {
          Button("Add Stock") { store.send(.addTapped) }
            .buttonStyle(.borderedProminent)
        }
      }
    }
  }

  private func rows(_ items: [WatchlistItem], section: WatchlistSection) -> some View {
    ForEach(items) { item in
      Button {
        store.send(.rowTapped(symbol: item.symbol))
      } label: {
        WatchlistRow(item: item, quote: store.quotes[item.symbol])
      }
      .swipeActions(edge: .leading) {
        Button {
          store.send(.favoriteSwiped(symbol: item.symbol))
        } label: {
          Label(item.isFavorite ? "Unfavorite" : "Favorite", systemImage: item.isFavorite ? "star.slash" : "star")
        }
        .tint(Palette.warning)
      }
      .swipeActions(edge: .trailing) {
        Button(role: .destructive) {
          store.send(.deleteSwiped(symbol: item.symbol))
        } label: {
          Label("Delete", systemImage: "trash")
        }
      }
    }
    .onMove { store.send(.moved(section, from: $0, to: $1)) }
  }
}

#Preview {
  WatchlistView(store: Store(initialState: WatchlistFeature.State()) {
    WatchlistFeature()
  } withDependencies: {
    $0.marketData = .previewValue
  })
}
