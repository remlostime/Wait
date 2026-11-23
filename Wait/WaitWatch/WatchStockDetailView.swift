//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import DesignSystem
import Domain
import SwiftUI

// MARK: - WatchStockDetailView

struct WatchStockDetailView: View {
  // MARK: Internal

  let row: WatchlistSnapshot.Row

  var body: some View {
    List {
      Section {
        header
      }
      if let distance = distanceText {
        Section("Buy") {
          Text(distance)
        }
      }
      Section("Ladder") {
        if row.ladder.rungs.isEmpty {
          Text("No target prices yet. Set them in Wait on iPhone.")
            .font(.footnote)
        } else {
          ForEach(row.ladder.rungs, id: \.rung) { rung in
            HStack {
              Text(rung.rung.title + (rung.isDerived ? " (derived)" : ""))
              Spacer()
              Text(rung.price.formatted(.currency(code: "USD")))
                .monospacedDigit()
            }
            .font(.footnote)
          }
        }
      }
    }
    .navigationTitle(row.symbol)
  }

  // MARK: Private

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(row.name)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(2)
      Text(WatchFormat.price(row.price))
        .font(.title3.monospacedDigit())
      if let change = WatchFormat.changePercent(row.changePercent) {
        Text(change)
          .font(.footnote.monospacedDigit())
          .foregroundStyle((row.changePercent ?? 0) < 0 ? Color.red : Color.green)
      }
      HStack {
        if let status = row.status {
          StatusPill(status: status, compact: true)
        }
        Spacer()
        if let temperature = row.temperature {
          Text(WatchFormat.temperature(temperature))
            .font(.headline.monospacedDigit())
        }
      }
    }
  }

  private var distanceText: String? {
    guard let price = row.price else {
      return nil
    }
    return WatchFormat.distanceToBuy(row.ladder.distanceToBuy(from: price))
  }
}

#if DEBUG
  #Preview {
    NavigationStack {
      WatchStockDetailView(row: WatchPreview.snapshot.rows[0])
    }
  }
#endif
