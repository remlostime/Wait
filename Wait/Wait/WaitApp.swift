// Created by kai_chen on 5/4/21.

import SwiftUI

@main
struct WaitApp: App {
  var body: some Scene {
    WindowGroup {
      let stock = Stock(
        ticker: "fb",
        name: "Facebook",
        currentPrice: 1.0,
        expectedPrice: 2.0)

      ContentView(stocks: [stock])
    }
  }
}
