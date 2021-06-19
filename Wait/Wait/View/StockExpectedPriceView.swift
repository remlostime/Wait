// Created by kai_chen on 5/4/21.

import Money
import SwiftUI

// MARK: - StockExpectedPriceView

struct StockExpectedPriceView: View {
  // MARK: Internal

  var searchStock: SearchStockResult
  @Binding var stock: Stock
  @Binding var isPresented: Bool

  var body: some View {
    HStack {
      NavigationView {
        VStack(alignment: .center) {
          Spacer()

          TextField("$0", text: $expectedPrice)
            .font(Font.system(size: 72))
            .multilineTextAlignment(.center)

          Spacer()

          Button("Add") {
            stock = Stock(
              symbol: searchStock.symbol,
              name: searchStock.name,
              currentPrice: 1.0,
              expectedPrice: Money<USD>(floatLiteral: Double(expectedPrice) ?? 0.0),
              changePercent: "1.8%",
              priceChartImage: nil
            )

            isPresented.toggle()
          }
          .font(.title)

          Spacer()
        }
        .padding()
        .navigationTitle(searchStock.symbol)
      }
    }
  }

  // MARK: Private

  @State private var expectedPrice = ""
}

// MARK: - WaitStockView_Previews

struct WaitStockView_Previews: PreviewProvider {
  static var previews: some View {
    StockExpectedPriceView(
      searchStock: SearchStockResult(symbol: "FB", name: "Facebook", exchange: "NYSE", country: "US", currency: "USD"),
      stock: .constant(Stock(symbol: "fb", name: "Facebook", currentPrice: 1.0, expectedPrice: 1.0, changePercent: "1.8%", priceChartImage: nil)),
      isPresented: .constant(true)
    )
  }
}
