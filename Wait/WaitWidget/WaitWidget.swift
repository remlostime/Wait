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
    // Sample data is for the widget gallery only. A real snapshot request shows what is on disk, or the empty state.
    let snapshot = context.isPreview ? WatchlistSnapshot.sample : SnapshotStore.appGroup.load()
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

  /// The time for today's quotes, and the date with the time for older ones, so yesterday's data doesn't look current.
  private static func quoteTime(_ date: Date) -> String {
    if Calendar.current.isDateInToday(date) {
      date.formatted(.dateTime.hour().minute())
    } else {
      date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
  }

  private func content(_ snapshot: WatchlistSnapshot) -> some View {
    let rows = Array(snapshot.rows.prefix(maxRows))
    return VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack {
        Text("Wait").font(.caption.weight(.bold)).foregroundStyle(Palette.accent)
        Spacer()
        if let asOf = snapshot.quotesAsOf {
          Text(Self.quoteTime(asOf)).font(.caption2).foregroundStyle(.secondary)
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
    // No `widgetURL`: the small widget can't hold `Link`s, so a tap opens the app, and the medium widget's rows are the only stock links.
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
