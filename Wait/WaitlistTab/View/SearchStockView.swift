// Created by kai_chen on 5/9/21.

import Alamofire
import Combine
import Model
import Networking
import Size
import StockDetailsFeature
import SwiftUI

// MARK: - SearchStockView

struct SearchStockView: View {
  @State private var keyword: String = ""
  @Binding var isPresented: Bool
  @Binding var stock: Stock

  @StateObject var dataSource = SearchStockDataSource()

  // TODO(Kai) - hard code it, since there's a bug in SwiftUI 16. Need to remove when it's fixed.
  var searchStocks = [
    SearchStockResult(symbol: "baba", name: "Baba", exchange: "ok", country: "ok", currency: "adsf"),
  ]

  var body: some View {
    NavigationView {
      List(dataSource.searchStocks, id: \.symbol) { searchStock in
        NavigationLink(destination: StockExpectedPriceInputView(searchStock: searchStock, stock: $stock, isPresented: $isPresented)) {
          SearchStockRow(stock: searchStock)
        }
      }
      .searchable(text: $keyword)
      .onChange(of: keyword, perform: { value in
        guard !keyword.isEmpty else {
          return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
          if keyword == value {
            dataSource.searchStocks(for: value)
          }
        }
      })
      .navigationTitle("Companies")
    }
  }
}

// MARK: - SearchStockView_Previews

struct SearchStockView_Previews: PreviewProvider {
  static var previews: some View {
    SearchStockView(
      isPresented: .constant(true),
      stock: .constant(Stock.empty)
    )
  }
}
