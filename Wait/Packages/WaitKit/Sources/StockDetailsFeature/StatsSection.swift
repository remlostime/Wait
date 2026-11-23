//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import DesignSystem
import Domain
import SwiftUI

// MARK: - StatsSection

/// Today's quote plus fundamentals from the backend profile (Finnhub ratios are percentages).
struct StatsSection: View {
  // MARK: Internal

  let quote: Quote?
  let profile: CompanyProfile?

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
          price("52W High", profile?.fiftyTwoWeekHigh ?? quote?.fiftyTwoWeekHigh)
          price("52W Low", profile?.fiftyTwoWeekLow ?? quote?.fiftyTwoWeekLow)
        }
        GridRow {
          stat("Mkt Cap", profile?.marketCap.map { "$" + $0.formatted(.number.notation(.compactName)) })
          stat("P/E", ratio(profile?.peRatio))
        }
        GridRow {
          stat("P/B", ratio(profile?.pbRatio))
          stat("Div Yield", percent(profile?.dividendYield))
        }
        GridRow {
          stat("ROE", percent(profile?.roe))
          stat("Beta", ratio(profile?.beta))
        }
        GridRow {
          stat("Volume", quote?.volume.map { $0.formatted(.number.notation(.compactName)) })
          stat("Change", quote?.changePercent.map { ($0 / 100).formatted(.percent.precision(.fractionLength(2))) })
        }
      }
      if let industry = profile?.industry {
        Text(industry).font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  // MARK: Private

  private func price(_ title: String, _ value: Decimal?) -> some View {
    stat(title, value.map { $0.formatted(.currency(code: "USD")) })
  }

  private func ratio(_ value: Double?) -> String? {
    value.map { $0.formatted(.number.precision(.fractionLength(2))) }
  }

  private func percent(_ value: Double?) -> String? {
    value.map { ($0 / 100).formatted(.percent.precision(.fractionLength(2))) }
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
