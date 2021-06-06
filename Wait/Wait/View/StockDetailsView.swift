// Created by kai_chen on 5/16/21.

import SwiftUI

// MARK: - StockDetailsView

struct StockDetailsView: View {
  var stock: Stock

  var body: some View {
    ScrollView {
      VStack(alignment: .leading) {
        Text(stock.symbol)
          .font(.subheadline)
        Text(stock.name)
          .font(.largeTitle)

        SwiftUIChartViewController()
          .frame(minHeight: 420.0)

        Spacer()

        Text(action)
          .foregroundColor(actionColor)
          .font(.largeTitle)

        HStack {
          Text("Expected Price")
          Spacer()
          Text(stock.expectedPrice.formattedCurrency)
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
  }

  var action: String {
    stock.currentPrice > stock.expectedPrice ? "Wait" : "Buy"
  }

  var actionColor: Color {
    stock.currentPrice > stock.expectedPrice ? .stockRed : .stockGreen
  }

  var comparedToCurrentPriceRate: String {
    let currentPrice = stock.currentPrice.amountDoubleValue ?? 0.0
    let expectedPrice = stock.expectedPrice.amountDoubleValue ?? 0.0

    if stock.currentPrice > stock.expectedPrice {
      let rate = (currentPrice - expectedPrice) / expectedPrice
      let percentage = String(format: "%.2f", rate * 100.0)
      return "Above \(percentage)%"
    } else {
      let rate = (expectedPrice - currentPrice) / expectedPrice
      let percentage = String(format: "%.2f", rate * 100.0)
      return "Below \(percentage)%"
    }
  }

  var comparedToCurrentPriceRateColor: Color {
    stock.currentPrice > stock.expectedPrice ? .stockRed : .stockGreen
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
