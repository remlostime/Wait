// Created by kai_chen on 5/4/21.

import SwiftUI

// MARK: - WaitStockView

struct WaitStockView: View {
  // MARK: Internal

  var searchStock: SearchStock
  @Binding var stock: Stock
  @Binding var isPresented: Bool

  var body: some View {
    VStack {
      HStack {
        Text("Ticker")
        Spacer()
        Text(searchStock.symbol)
      }
      .padding()

      HStack {
        Text("Price")
        Spacer()
        TextField("Price", text: $expectedPrice)
      }
      .padding()

      Spacer()

      Button("Add") {
        stock = Stock(ticker: searchStock.symbol, name: searchStock.name, currentPrice: 1.0, expectedPrice: Double(expectedPrice) ?? 0.0)
        isPresented.toggle()
      }

      Spacer()
    }
  }

  // MARK: Private

  @State private var expectedPrice = "1.0"
}

// MARK: - WaitStockView_Previews

struct WaitStockView_Previews: PreviewProvider {
  static var previews: some View {
    WaitStockView(
      searchStock: SearchStock(symbol: "fb", name: "facebook", matchScore: "23.0", region: "US"),
      stock: .constant(Stock(ticker: "fb", name: "Facebook", currentPrice: 1.0, expectedPrice: 1.0)),
      isPresented: .constant(true))
  }
}
