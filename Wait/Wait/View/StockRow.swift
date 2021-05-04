// Created by kai_chen on 5/4/21.

import SwiftUI

struct StockRow: View {
  let stock: Stock

  var body: some View {
    HStack {
      Text(stock.name)

      Spacer()

      Text(String(format: "%.2f", stock.expectedPrice))

      Text(String(format: "%.2f", stock.currentPrice))
    }
  }
}

struct StockRow_Previews: PreviewProvider {
  static var previews: some View {
    let stock = Stock(
      ticker: "fb",
      name: "Facebook",
      currentPrice: 1.0,
      expectedPrice: 2.0)

    StockRow(stock: stock)
  }
}
