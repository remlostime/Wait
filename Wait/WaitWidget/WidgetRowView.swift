//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import DesignSystem
import Domain
import SwiftUI

// MARK: - WidgetRowView

struct WidgetRowView: View {
  let row: WatchlistSnapshot.Row
  let compact: Bool

  var body: some View {
    HStack(spacing: Spacing.xs) {
      Text(row.symbol).font(.caption.weight(.semibold)).lineLimit(1)
      Spacer(minLength: Spacing.xxs)
      if !compact, let price = row.price {
        Text(price, format: .currency(code: "USD")).font(.caption.monospacedDigit())
      }
      if !compact, let change = row.changePercent {
        Text(change / 100, format: .percent.precision(.fractionLength(1)))
          .font(.caption2.monospacedDigit())
          .foregroundStyle(Palette.change(change))
      }
      StatusPill(status: row.status, compact: true)
      if !compact {
        TemperatureBadge(temperature: row.temperature.map(Temperature.init(value:)))
      }
    }
  }
}
