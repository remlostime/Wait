//
// Created by: kai_chen on 8/22/21.
// Copyright © 2021 Wait. All rights reserved.
//

import DesignSystem
import Domain
import Persistence
import SwiftUI
import WidgetKit

// MARK: - SnapshotEntry

struct SnapshotEntry: TimelineEntry {
  let date: Date
  let snapshot: WatchlistSnapshot?
}

// MARK: - SnapshotProvider

/// Reads `snapshot.json` from the app group. Refreshing is driven by the app (`WidgetCenter.reloadAllTimelines`), with a 30-minute fallback.
struct SnapshotProvider: TimelineProvider {
  func placeholder(in context: Context) -> SnapshotEntry {
    SnapshotEntry(date: .now, snapshot: .sample)
  }

  func getSnapshot(in context: Context, completion: @escaping @Sendable (SnapshotEntry) -> Void) {
    let snapshot = context.isPreview ? WatchlistSnapshot.sample : (SnapshotStore.appGroup.load() ?? .sample)
    completion(SnapshotEntry(date: .now, snapshot: snapshot))
  }

  func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<SnapshotEntry>) -> Void) {
    let entry = SnapshotEntry(date: .now, snapshot: SnapshotStore.appGroup.load())
    completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
  }
}

// MARK: - WaitWidgetEntryView

struct WaitWidgetEntryView: View {
  // MARK: Internal

  let entry: SnapshotEntry

  var body: some View {
    Group {
      if let snapshot = entry.snapshot, !snapshot.rows.isEmpty {
        content(snapshot)
      } else {
        empty
      }
    }
    .containerBackground(.fill.tertiary, for: .widget)
  }

  // MARK: Private

  @Environment(\.widgetFamily) private var family

  private var maxRows: Int {
    family == .systemSmall ? 3 : 4
  }

  private var empty: some View {
    VStack(spacing: Spacing.s) {
      Image(systemName: "chart.line.uptrend.xyaxis").font(.title2).foregroundStyle(Palette.accent)
      Text("Add stocks in Wait").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }
  }

  /// The same format as `AppFeature.DeepLink`, which the widget can't import.
  private static func stockURL(_ symbol: String) -> URL {
    URL(string: "wait://stock/\(symbol)")!
  }

  private func content(_ snapshot: WatchlistSnapshot) -> some View {
    let rows = Array(snapshot.rows.prefix(maxRows))
    return VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack {
        Text("Wait").font(.caption.weight(.bold)).foregroundStyle(Palette.accent)
        Spacer()
        if let asOf = snapshot.quotesAsOf {
          Text(asOf, style: .time).font(.caption2).foregroundStyle(.secondary)
        }
      }
      ForEach(rows) { row in
        if family == .systemSmall {
          WidgetRowView(row: row, compact: true)
        } else {
          Link(destination: Self.stockURL(row.symbol)) {
            WidgetRowView(row: row, compact: false)
          }
        }
      }
      Spacer(minLength: 0)
    }
    .widgetURL(rows.first.map { Self.stockURL($0.symbol) })
  }
}

// MARK: - WaitWidget

@main
struct WaitWidget: Widget {
  let kind = "WaitWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
      WaitWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("Watchlist")
    .description("Your watchlist with ladder status and temperature.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

// MARK: - Sample

extension WatchlistSnapshot {
  static let sample = WatchlistSnapshot(
    generatedAt: .now,
    quotesAsOf: .now,
    rows: [
      .init(symbol: "AAPL", name: "Apple", price: Decimal(string: "189.98"), changePercent: 1.24, status: .watch, temperature: 52, ladder: .empty, isFavorite: true),
      .init(symbol: "PINS", name: "Pinterest", price: Decimal(string: "14.20"), changePercent: -0.8, status: .buyZone, temperature: 21, ladder: .empty, isFavorite: false),
      .init(symbol: "MSFT", name: "Microsoft", price: Decimal(string: "414.25"), changePercent: 0.4, status: .trim, temperature: 84, ladder: .empty, isFavorite: false),
    ]
  )
}

#Preview(as: .systemMedium) {
  WaitWidget()
} timeline: {
  SnapshotEntry(date: .now, snapshot: .sample)
  SnapshotEntry(date: .now, snapshot: nil)
}
