// Created by kai_chen on 5/9/21.

import Alamofire
import Combine
import Model
import Networking
import Size
import SwiftUI

// MARK: - SearchStockView

struct SearchStockView: View {
  @State private var keyword: String = ""
  @Binding var isPresented: Bool
  @Binding var stock: Stock

  @ObservedObject var dataSource = SearchStockDataSource()

  var body: some View {
    VStack {
      List {
        ForEach(dataSource.searchStocks, id: \.symbol) { searchStock in
          NavigationLink(destination: StockExpectedPriceInputView(searchStock: searchStock, stock: $stock, isPresented: $isPresented)) {
            SearchStockRow(stock: searchStock)
          }
        }
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

// MARK: - SearchStockView_Previews

struct SearchStockView_Previews: PreviewProvider {
  static var previews: some View {
    SearchStockView(
      isPresented: .constant(true),
      stock: .constant(.empty)
    )
  }
}
