// Created by kai_chen on 5/4/21.

import SwiftUI

struct WaitStockView: View {
  @Binding var stock: Stock?
  @Binding var isPresented: Bool
  @Binding var ticker: String
  @Binding var price: String

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
        TextField("Price", text: $price)
      }
      .padding()

      Spacer()

      Button("Add") {
        stock = Stock(ticker: ticker, name: "xx", currentPrice: 1.0, expectedPrice: Double(price) ?? 0.0)
        isPresented.toggle()
      }

      Spacer()
    }
  }
}

struct WaitStockView_Previews: PreviewProvider {
  static var previews: some View {
    WaitStockView(stock: .constant(nil), isPresented: .constant(true), ticker: .constant("fb"), price: .constant("1.0"))
  }
}
