// Created by kai_chen on 5/4/21.

import Cache
import SwiftUI
import SwiftyBeaver

let logger = SwiftyBeaver.self

@main
struct WaitApp: App {
  var body: some Scene {
    WindowGroup {
      let stocks = getStocks()

      ContentView(stocks: stocks)
    }
  }

  func setupLogger() {

  }

  func getStocks() -> [Stock] {
    let diskConfig = DiskConfig(name: "stocks")
    let memoryConfig = MemoryConfig()

    let storage = try? Storage<String, [Stock]>(
      diskConfig: diskConfig,
      memoryConfig: memoryConfig,
      transformer: TransformerFactory.forCodable(ofType: [Stock].self)
    )

    guard let stocks = try? storage?.object(forKey: "stocks") else {
      return []
    }

    return stocks
  }
}
