//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import DesignSystem
import Domain
import SwiftUI

// MARK: - WatchlistRow

struct WatchlistRow: View {
  // MARK: Internal

  let item: WatchlistItem
  let quote: Quote?

  var body: some View {
    HStack(spacing: Spacing.m) {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        HStack(spacing: Spacing.xs) {
          Text(item.symbol).font(.headline)
          if item.isFavorite {
            Image(systemName: "star.fill").font(.caption2).foregroundStyle(Palette.warning)
          }
        }
        Text(item.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
      }
      Spacer(minLength: Spacing.s)
      VStack(alignment: .trailing, spacing: Spacing.xxs) {
        if let quote {
          Text(quote.price, format: .currency(code: "USD")).font(.body.monospacedDigit())
          if let change = quote.changePercent {
            Text(change / 100, format: .percent.precision(.fractionLength(2)))
              .font(.caption.monospacedDigit())
              .foregroundStyle(Palette.change(change))
          }
        } else {
          Text("—").foregroundStyle(.secondary)
        }
      }
      VStack(alignment: .trailing, spacing: Spacing.xxs) {
        StatusPill(status: status, compact: true)
        TemperatureBadge(temperature: temperature)
      }
    }
    .foregroundStyle(.primary)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  // MARK: Private

  private var status: LadderStatus? {
    quote.map { item.ladder.status(at: $0.price) }
  }

  private var temperature: Temperature? {
    quote.flatMap { item.ladder.temperature(at: $0.price) }
  }
}
