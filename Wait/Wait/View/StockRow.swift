// Created by kai_chen on 5/4/21.

import SwiftUI

// MARK: - StockRow

struct StockRow: View {
  // MARK: Internal

  let stock: Stock

  var body: some View {
    HStack {
      VStack(alignment: .leading) {
        Text(stock.symbol)
          .font(.title3)
        Text(stock.name)
          .font(.subheadline)
          .lineLimit(1)
          .foregroundColor(.secondary)
      }

      Spacer()

      VStack(alignment: .trailing) {
        Text(stock.currentPrice.formattedCurrency)
          .font(.title3)
        Text(stock.changePercent)
          .font(.subheadline)
          .foregroundColor(isNegativeNumber(stock.changePercent) ? .red : .green)
      }
    }
    .padding()
  }

  // MARK: Private

  private func isNegativeNumber(_ number: String) -> Bool {
    guard !number.isEmpty else {
      return false
    }

    return number.first == "-"
  }
}

// MARK: - StockRow_Previews

struct StockRow_Previews: PreviewProvider {
  static var previews: some View {
    let stock = Stock(
      symbol: "fb",
      name: "Facebook Inc - Class A Share",
      currentPrice: 100.0,
      expectedPrice: 200.0,
      changePercent: "1.8%"
    )

    StockRow(stock: stock)
  }
}
