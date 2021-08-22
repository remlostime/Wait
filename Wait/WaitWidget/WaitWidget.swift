//
// Created by: kai_chen on 8/22/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Model
import Size
import SwiftUI
import WidgetKit

// MARK: - Provider

struct Provider: TimelineProvider {
  // MARK: Internal

  func placeholder(in context: Context) -> WaitEntry {
    WaitEntry.snapshot
  }

  func getSnapshot(in context: Context, completion: @escaping (WaitEntry) -> Void) {
    let entry = WaitEntry.snapshot
    completion(entry)
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    var stocks = StockCache.shared.getStocks()
    let maxCount = 3
    stocks = Array(stocks[..<min(maxCount, stocks.count)])
    let group = DispatchGroup()
    for (index, stock) in stocks.enumerated() {
      group.enter()
      stockCurrentQuoteNetworkClient.fetchStockDetails(stock: stock) { stock in
        if let stock = stock {
          stocks[index] = stock
        }

        group.leave()
      }
    }

    group.notify(queue: DispatchQueue.main) {
      let currentDate = Date()
      let entry = WaitEntry(date: currentDate, stocks: stocks)
      let timeline = Timeline(entries: [entry], policy: .atEnd)
      completion(timeline)
    }
  }

  // MARK: Private

  private let stockCurrentQuoteNetworkClient = StockCurrentQuoteNetworkClient()
}

// MARK: - WaitEntry

struct WaitEntry: TimelineEntry {
  let date: Date
  let stocks: [Stock]
}

extension WaitEntry {
  static let snapshot = WaitEntry(date: Date(), stocks: [Stock.empty])
}

// MARK: - WaitWidgetEntryView

struct WaitWidgetEntryView: View {
  var entry: Provider.Entry

  var body: some View {
    VStack {
      ForEach(entry.stocks, id: \.symbol) { stock in
        WidgetStockRow(stock: stock)
      }
      .padding(.all, Size.horizontalPadding8)
    }
  }
}

// MARK: - WaitWidget

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

// MARK: - WaitWidget_Previews

struct WaitWidget_Previews: PreviewProvider {
  static var previews: some View {
    WaitWidgetEntryView(entry: WaitEntry.snapshot)
      .previewContext(WidgetPreviewContext(family: .systemSmall))
  }
}
