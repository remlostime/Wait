// Created by kai_chen on 5/4/21.

import SwiftUI

// MARK: - StockExpectedPriceView

struct StockExpectedPriceView: View {
  // MARK: Internal

  var searchStock: SearchStock
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
              expectedPrice: Double(expectedPrice) ?? 0.0,
              changePercent: "1.8%"
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
      searchStock: SearchStock(symbol: "fb", name: "facebook", matchScore: "23.0", region: "US"),
      stock: .constant(Stock(symbol: "fb", name: "Facebook", currentPrice: 1.0, expectedPrice: 1.0, changePercent: "1.8%")),
      isPresented: .constant(true)
    )
  }
}
