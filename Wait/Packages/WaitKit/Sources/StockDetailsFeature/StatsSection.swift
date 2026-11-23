//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import DesignSystem
import Domain
import SwiftUI

// MARK: - StatsSection

/// Quote-derived stats. The legacy screen showed Alpha Vantage OVERVIEW fundamentals, which are now Premium; plan 04 brings fundamentals back from the backend.
struct StatsSection: View {
  // MARK: Internal

  let quote: Quote?

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.m) {
      Text("Stats").font(.headline)
      Grid(alignment: .leading, horizontalSpacing: Spacing.l, verticalSpacing: Spacing.m) {
        GridRow {
          price("Open", quote?.open)
          price("Prev Close", quote?.previousClose)
        }
        GridRow {
          price("High", quote?.high)
          price("Low", quote?.low)
        }
        GridRow {
          price("52W High", quote?.fiftyTwoWeekHigh)
          price("52W Low", quote?.fiftyTwoWeekLow)
        }
        GridRow {
          stat("Volume", quote?.volume.map { $0.formatted(.number.notation(.compactName)) })
          stat("Change", quote?.changePercent.map { ($0 / 100).formatted(.percent.precision(.fractionLength(2))) })
        }
      }
    }
  }

  // MARK: Private

  private func price(_ title: String, _ value: Decimal?) -> some View {
    stat(title, value.map { $0.formatted(.currency(code: "USD")) })
  }

  private func stat(_ title: String, _ value: String?) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      Text(value ?? "—").font(.subheadline.monospacedDigit())
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}
