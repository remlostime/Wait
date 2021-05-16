// Created by kai_chen on 5/16/21.

import SwiftUI

// MARK: - StockDetailsView

struct StockDetailsView: View {
  var stock: Stock

  var body: some View {
    VStack(alignment: .leading) {
      Text(stock.symbol)
        .font(.subheadline)
      Text(stock.name)
        .font(.largeTitle)
      Text(String(stock.currentPrice))
        .font(.largeTitle)

      Spacer()

      Text(action)
        .foregroundColor(actionColor)
        .font(.largeTitle)

      HStack {
        Text("Expected Price")
        Spacer()
        Text(String(stock.expectedPrice))
      }

      HStack {
        Text("Current price")
        Spacer()
        Text(comparedToCurrentPriceRate)
          .foregroundColor(comparedToCurrentPriceRateColor)
      }

      Spacer()
    }
    .multilineTextAlignment(.leading)
    .padding()
  }

  var action: String {
    stock.currentPrice > stock.expectedPrice ? "Wait" : "Buy"
  }

  var actionColor: Color {
    stock.currentPrice > stock.expectedPrice ? .red : .green
  }

  var comparedToCurrentPriceRate: String {
    if stock.currentPrice > stock.expectedPrice {
      let rate = (stock.currentPrice - stock.expectedPrice) / stock.expectedPrice
      let percentage = "\(rate * 100.0)%"
      return "Above \(percentage)"
    } else {
      let rate = (stock.expectedPrice - stock.currentPrice) / stock.expectedPrice
      let percentage = "\(rate * 100.0)%"
      return "Below \(percentage)"
    }
  }

  var comparedToCurrentPriceRateColor: Color {
    stock.currentPrice > stock.expectedPrice ? .red : .green
  }
}

// MARK: - StockDetailsView_Previews

struct StockDetailsView_Previews: PreviewProvider {
  static var previews: some View {
    let stock = Stock(
      symbol: "fb",
      name: "Facebook",
      currentPrice: 1.0,
      expectedPrice: 2.0,
      changePercent: "1.8%"
    )

    StockDetailsView(stock: stock)
  }
}
