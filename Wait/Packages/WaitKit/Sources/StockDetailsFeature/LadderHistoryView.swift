//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Charts
import DesignSystem
import Domain
import SwiftUI

// MARK: - LadderHistoryView

struct LadderHistoryView: View {
  // MARK: Internal

  let history: [LadderRevision]

  var body: some View {
    List {
      let charted = history.filter { $0.ladder.buyHigh != nil }
      if charted.count > 1 {
        Section {
          Chart(Array(charted.enumerated()), id: \.offset) { _, revision in
            LineMark(x: .value("Date", revision.date), y: .value("Buy high", revision.ladder.buyHigh?.doubleValue ?? 0))
              .interpolationMethod(.stepEnd)
            PointMark(x: .value("Date", revision.date), y: .value("Buy high", revision.ladder.buyHigh?.doubleValue ?? 0))
          }
          .frame(height: 160)
        } header: {
          Text("Buy high over time")
        }
      }
      Section {
        ForEach(Array(history.enumerated().reversed()), id: \.offset) { _, revision in
          VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(revision.date, format: .dateTime.year().month().day()).font(.subheadline.weight(.semibold))
            Text(summary(revision.ladder)).font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    }
    .overlay {
      if history.isEmpty {
        ContentUnavailableView("No history yet", systemImage: "clock")
      }
    }
    .navigationTitle("Ladder History")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Done") { dismiss() }
      }
    }
  }

  // MARK: Private

  @Environment(\.dismiss) private var dismiss

  private func summary(_ ladder: PriceLadder) -> String {
    ladder.rungs
      .filter { !$0.isDerived }
      .map { "\($0.rung.title) \($0.price.formatted(.currency(code: "USD")))" }
      .joined(separator: " · ")
  }
}
