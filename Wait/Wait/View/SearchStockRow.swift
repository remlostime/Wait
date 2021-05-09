// Created by kai_chen on 5/9/21.

import SwiftUI

struct SearchStockRow: View {
  var stock: SearchStock
  
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

struct SearchStockRow_Previews: PreviewProvider {
  static var previews: some View {
    SearchStockRow(stock: SearchStock(symbol: "FB", name: "Facebook", matchScore: "1.0", region: "US"))
  }
}
