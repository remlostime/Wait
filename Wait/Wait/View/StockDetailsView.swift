// Created by kai_chen on 5/4/21.

import SwiftUI

// MARK: - StockDetailsView

struct StockDetailsView: View {
  // MARK: Internal

  var searchStock: SearchStock
  @Binding var stock: Stock
  @Binding var isPresented: Bool

  var body: some View {
    HStack {
      NavigationView {
        VStack {
          TextField("Expected Price", text: $expectedPrice)
            .padding()

          HStack(alignment: .center, spacing: 32.0) {
            Button("Cancel") {
              isPresented.toggle()
            }

            Button("Add") {
              stock = Stock(ticker: searchStock.symbol, name: searchStock.name, currentPrice: 1.0, expectedPrice: Double(expectedPrice) ?? 0.0)
              isPresented.toggle()
            }
          }
          .padding()

          Spacer()
        }
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
    StockDetailsView(
      searchStock: SearchStock(symbol: "fb", name: "facebook", matchScore: "23.0", region: "US"),
      stock: .constant(Stock(ticker: "fb", name: "Facebook", currentPrice: 1.0, expectedPrice: 1.0)),
      isPresented: .constant(true)
    )
  }
}
