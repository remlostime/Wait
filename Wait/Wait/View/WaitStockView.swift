// Created by kai_chen on 5/4/21.

import SwiftUI

// MARK: - WaitStockView

struct WaitStockView: View {
  @Binding var stock: Stock
  @Binding var isPresented: Bool

  var body: some View {
    VStack {
      HStack {
        Text("Ticker")
        Spacer()
        TextField("Ticker", text: $ticker)
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
        stock = Stock(ticker: ticker, name: "XX", currentPrice: 1.0, expectedPrice: Double(expectedPrice) ?? 0.0)
        isPresented.toggle()
      }

      Spacer()
    }
  }

  @State private var ticker = "FB"
  @State private var expectedPrice = "1.0"
}

// MARK: - WaitStockView_Previews

struct WaitStockView_Previews: PreviewProvider {
  static var previews: some View {
    WaitStockView(stock: .constant(Stock(ticker: "fb", name: "Facebook", currentPrice: 1.0, expectedPrice: 1.0)), isPresented: .constant(true))
  }
}
