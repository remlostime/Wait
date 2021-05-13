// Created by kai_chen on 5/4/21.

import Shake
import SwiftUI
import SwiftyBeaver

let logger = SwiftyBeaver.self

// MARK: - WaitApp

@main
struct WaitApp: App {
  // MARK: Lifecycle

  init() {
    setupShake()
    setupLogger()
  }

  // MARK: Internal

  var body: some Scene {
    WindowGroup {
      let stocks = StockCache.shared.getStocks()
      ContentView(stocks: stocks)
    }
  }

  // MARK: Private

  private func setupShake() {
    Shake.start(
      clientId: "EMFDruyQ3NpZJixuCtgi2LiTl83hjfngf3tRFL3F",
      clientSecret: "wh1riTvDR93wmB0itrbltVmOKMsFToZyM4O6Y65pPtARpvdiLq4Xtd1"
    )
  }

  private func setupLogger() {
    let console = ConsoleDestination()
    let file = FileDestination()
    SwiftyBeaver.addDestination(console)
    SwiftyBeaver.addDestination(file)
  }
}
