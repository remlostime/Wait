//
// Created by: kai_chen on 8/22/21.
// Copyright © 2021 Wait. All rights reserved.
//

import WidgetKit
import SwiftUI
import Model

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> WaitEntry {
    return WaitEntry.snapshot
  }

  func getSnapshot(in context: Context, completion: @escaping (WaitEntry) -> ()) {
    let entry = WaitEntry.snapshot
    completion(entry)
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
    let stocks = StockCache.shared.getStocks()
    let currentDate = Date()
    let entry = WaitEntry(date: currentDate, stocks: stocks)

    let timeline = Timeline(entries: [entry], policy: .atEnd)
    completion(timeline)
  }
}

struct WaitEntry: TimelineEntry {
  let date: Date
  let stocks: [Stock]
}

extension WaitEntry {
  static let snapshot = WaitEntry(date: Date(), stocks: [Stock.empty])
}

struct WaitWidgetEntryView : View {
  var entry: Provider.Entry
  var stocks: [Stock] {
    let maxCount = 3
    return Array(entry.stocks[..<min(maxCount, entry.stocks.count)])
  }

  var body: some View {
    VStack {
      ForEach(stocks, id: \.symbol) { stock in
        WidgetStockRow(stock: stock)
      }
      .padding()
    }
  }
}

@main
struct WaitWidget: Widget {
  let kind: String = "WaitWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: Provider()) { entry in
      WaitWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("My Widget")
    .description("This is an example widget.")
  }
}

struct WaitWidget_Previews: PreviewProvider {
  static var previews: some View {
    WaitWidgetEntryView(entry: WaitEntry.snapshot)
      .previewContext(WidgetPreviewContext(family: .systemSmall))
  }
}
