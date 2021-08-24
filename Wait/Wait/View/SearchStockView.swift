// Created by kai_chen on 5/9/21.

import Alamofire
import Combine
import Model
import Networking
import Size
import SwiftUI
import SwiftUIX
import SwiftyJSON

// MARK: - SearchStockView

struct SearchStockView: View {
  @State private var keyword: String = ""
  @Binding var isPresented: Bool
  @Binding var stock: Stock

  @ObservedObject var dataSource = SearchStockDataSource()

  var body: some View {
    VStack {
      SearchBar("Search Stock", text: $keyword) { _ in
        if keyword.isEmpty {
          dataSource.searchStocks(for: keyword)
        }
      } onCommit: {
        dataSource.searchStocks(for: keyword)
      }
      .onChange(of: keyword) { value in
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
          if keyword == value {
            dataSource.searchStocks(for: value)
          }
        }
      }

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
