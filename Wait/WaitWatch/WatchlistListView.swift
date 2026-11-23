//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Connectivity
import Domain
import SwiftUI

// MARK: - WatchlistListView

struct WatchlistListView: View {
  // MARK: Internal

  let store: WatchSnapshotStore

  var body: some View {
    Group {
      if store.isEmpty {
        ContentUnavailableView {
          Label("No stocks yet", systemImage: "iphone")
        } description: {
          Text("Open Wait on iPhone")
        }
      } else {
        list
      }
    }
    .navigationTitle("Wait")
    .navigationDestination(for: String.self) { symbol in
      if let row = store.row(symbol: symbol) {
        WatchStockDetailView(row: row)
      } else {
        Text("\(symbol) is no longer on your watchlist")
      }
    }
  }

  // MARK: Private

  private var list: some View {
    List {
      if !store.favorites.isEmpty {
        Section("Favorites") {
          rows(store.favorites)
        }
      }
      if !store.others.isEmpty {
        Section {
          rows(store.others)
        } header: {
          if !store.favorites.isEmpty {
            Text("Watchlist")
          }
        }
      }
      if let quotesAsOf = store.snapshot?.quotesAsOf {
        Section {
          Text("Quotes \(quotesAsOf.formatted(.relative(presentation: .named)))")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private func rows(_ rows: [WatchlistSnapshot.Row]) -> some View {
    ForEach(rows) { row in
      NavigationLink(value: row.symbol) {
        WatchlistRowView(row: row)
      }
    }
  }
}

#if DEBUG
  #Preview {
    let store = WatchPreview.store()
    NavigationStack {
      WatchlistListView(store: store)
    }
    .task { await store.start() }
  }

  #Preview("Empty") {
    NavigationStack {
      WatchlistListView(store: WatchSnapshotStore(connectivity: .noop))
    }
  }
#endif
