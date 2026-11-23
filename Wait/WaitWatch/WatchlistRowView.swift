//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import DesignSystem
import Domain
import SwiftUI

// MARK: - WatchlistRowView

struct WatchlistRowView: View {
  let row: WatchlistSnapshot.Row

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(row.symbol)
          .font(.headline)
        Spacer()
        if let temperature = row.temperature {
          Text(WatchFormat.temperature(temperature))
            .font(.headline.monospacedDigit())
        }
      }
      HStack {
        Text(WatchFormat.price(row.price))
          .font(.subheadline.monospacedDigit())
          .foregroundStyle(.secondary)
        Spacer()
        if let status = row.status {
          StatusPill(status: status, compact: true)
        }
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }
}
