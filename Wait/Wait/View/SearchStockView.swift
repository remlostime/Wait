// Created by kai_chen on 5/9/21.

import Alamofire
import Model
import Networking
import SwiftUI
import SwiftyJSON
import Combine

// MARK: - SearchStockView

struct SearchStockView: View {
  @State private var keyword: String = ""
  @Binding var isPresented: Bool
  @Binding var stock: Stock

  @ObservedObject var dataSource = SearchStockDataSource()

  var body: some View {
    VStack {
      SearchBar(keyword: $keyword.onChange(keywordDidChange))

      List {
        ForEach(dataSource.searchStocks, id: \.symbol) { searchStock in
          NavigationLink(destination: StockExpectedPriceInputView(searchStock: searchStock, stock: $stock, isPresented: $isPresented)) {
            SearchStockRow(stock: searchStock)
          }
        }
      }
    }
    .navigationTitle("Companies")
  }

  func keywordDidChange(to newKeyword: String) {
    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
      guard newKeyword == keyword else {
        return
      }

      dataSource.searchStocks(for: keyword)
    }
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
