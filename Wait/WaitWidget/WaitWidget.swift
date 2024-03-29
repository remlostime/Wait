//
// Created by: kai_chen on 8/22/21.
// Copyright © 2021 Wait. All rights reserved.
//

import CacheService
import Combine
import Logging
import Model
import Networking
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

    Logger.shared.verbose("I am here")
    stockCurrentQuoteNetworkClient.fetchDetails(stocks: stocks)
      .sink { result in
        let symbols = stocks.map { $0.symbol }
        switch result {
          case .finished:
            Logger.shared.verbose("Successfully fetch stocks: \(symbols)")
          case let .failure(error):
            Logger.shared.error("Failed to fetch stock: \(symbols). Error: \(error.localizedDescription)")
        }
      } receiveValue: { stockQuoteBatch in
        Logger.shared.verbose("I am here ahahah")
        let newStocks: [Stock] = stocks.map {
          if let quote = stockQuoteBatch.quotes[$0.symbol] {
            return $0.with(currentQuote: quote)
          } else {
            return $0
          }
        }

        DispatchQueue.main.async {
          let currentDate = Date()
          let entry = WaitEntry(date: currentDate, stocks: newStocks)
          let timeline = Timeline(entries: [entry], policy: .atEnd)
          completion(timeline)
        }
      }
      .store(in: &subscriptions)
  }

  // MARK: Private

  @State private var subscriptions: Set<AnyCancellable> = []
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
