// Created by kai_chen on 5/4/21.

import Model
import Money
import Size
import SwiftUI

// MARK: - StockExpectedPriceInputView

struct StockExpectedPriceInputView: View {
  // MARK: Internal

  class ExpectedPriceModel: ObservableObject {
    @Published var formattedPrice = "" {
      didSet {
        if let prefix = formattedPrice.first, prefix != "$" {
          formattedPrice = "$" + formattedPrice
        }
      }
    }

    var price: String {
      var _price = formattedPrice
      while let prefix = _price.first, prefix == "$" {
        _price = String(_price.dropFirst())
      }

      return _price
    }
  }

  var searchStock: SearchStockResult
  @Binding var stock: Stock
  @Binding var isPresented: Bool

  var body: some View {
    VStack(alignment: .center) {
      Spacer()

      TextField("$0", text: $expectedPriceModel.formattedPrice)
        .multilineTextAlignment(.center)
        .font(Font.system(size: Size.size72))
        .keyboardType(.numberPad)

      Spacer()

      Button("Add") {
        stock = Stock(
          symbol: searchStock.symbol,
          name: searchStock.name,
          expectedPrice: Money<USD>(floatLiteral: Double(expectedPriceModel.price) ?? 0.0),
          currentQuote: .empty
        )

        isPresented.toggle()
      }
      .font(.title)
    }
    .padding(.bottom, Size.verticalPadding24)
    .navigationTitle(searchStock.name)
  }

  // MARK: Private

  @ObservedObject private var expectedPriceModel = ExpectedPriceModel()
}

// MARK: - WaitStockView_Previews

struct WaitStockView_Previews: PreviewProvider {
  static var previews: some View {
    StockExpectedPriceInputView(
      searchStock: SearchStockResult(symbol: "FB", name: "Facebook", exchange: "NYSE", country: "US", currency: "USD"),
      stock: .constant(Stock.empty),
      isPresented: .constant(true)
    )
  }
}
