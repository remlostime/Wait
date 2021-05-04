// Created by kai_chen on 5/4/21.

import SwiftUI

struct WaitStockView: View {
  @Binding var ticker: String
  @Binding var price: String

  var body: some View {
    VStack {
      HStack {
        Text("Ticker")
        TextField("Ticker", text: $ticker)
      }

      HStack {
        Text("Price")
        TextField("Price", text: $price)
      }

      Spacer()

      Button("Add") {
      }

      Spacer()
    }
  }
}

struct WaitStockView_Previews: PreviewProvider {
  static var previews: some View {
    WaitStockView(ticker: .constant("FB"), price: .constant("10.0"))
  }
}
