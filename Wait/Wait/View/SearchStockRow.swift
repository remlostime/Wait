// Created by kai_chen on 5/9/21.

import SwiftUI

// MARK: - SearchStockRow

struct SearchStockRow: View {
  var stock: SearchStockResult

  var body: some View {
    HStack {
      Text(stock.symbol)
        .font(.title3)

      Spacer()

      Text(stock.name)
        .font(.subheadline)
        .foregroundColor(.gray)
    }
  }
}

// MARK: - SearchStockRow_Previews

struct SearchStockRow_Previews: PreviewProvider {
  static var previews: some View {
    SearchStockRow(stock: SearchStockResult(symbol: "FB", name: "Facebook", exchange: "NYSE", country: "US", currency: "USD"))
  }
}
