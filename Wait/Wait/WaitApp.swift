// Created by kai_chen on 5/4/21.

import SwiftUI
import SwiftyBeaver

let logger = SwiftyBeaver.self

// MARK: - WaitApp

@main
struct WaitApp: App {
  var body: some Scene {
    WindowGroup {
      let stocks = StockCache.shared.getStocks()

      ContentView(stocks: stocks)
    }
  }

  func setupLogger() {}
}
