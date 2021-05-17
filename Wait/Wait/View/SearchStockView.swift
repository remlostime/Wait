// Created by kai_chen on 5/9/21.

import Alamofire
import SwiftUI
import SwiftyJSON

// MARK: - SearchStockView

struct SearchStockView: View {
  @State private var keyword: String = ""
  @State private var searchStocks: [SearchStock] = []
  @Binding var isPresented: Bool
  @Binding var stock: Stock

  var body: some View {
    VStack {
      SearchBar(keyword: $keyword.onChange(keywordDidChange))

      List {
        ForEach(searchStocks, id: \.symbol) { searchStock in
          NavigationLink(destination: StockExpectedPriceView(searchStock: searchStock, stock: $stock, isPresented: $isPresented)) {
            SearchStockRow(stock: searchStock)
          }
        }
      }
    }
  }

  private func buildStockSearchURL(keyword: String) -> URL? {
    let params = [
      "function": "SYMBOL_SEARCH",
      "keywords": keyword,
    ]

    let url = NetworkingURLBuilder.buildURL(api: "query", params: params)

    return url
  }

  func searchStocks(for keyword: String) {
    guard let url = buildStockSearchURL(keyword: keyword) else {
      return
    }

    AF.request(url).validate().responseData { response in
      switch response.result {
        case let .success(data):
          let decoder = JSONDecoder()

          guard
            let json = try? JSON(data: data),
            let rawData = try? json["bestMatches"].rawData(),
            let newSearchStocks = try? decoder.decode([SearchStock].self, from: rawData)
          else {
            logger.error("Failed to decode search stock")
            return
          }

          searchStocks = newSearchStocks
        case let .failure(error):
          logger.error("Failed to search stock: \(error.localizedDescription)")
      }
    }
  }

  func keywordDidChange(to newKeyword: String) {
    searchStocks(for: newKeyword)
  }
}

// MARK: - SearchStockView_Previews

struct SearchStockView_Previews: PreviewProvider {
  static var previews: some View {
    SearchStockView(
      isPresented: .constant(true),
      stock: .constant(
        Stock(symbol: "FB",
              name: "Facebook",
              currentPrice: 1.0,
              expectedPrice: 1.0,
              changePercent: "1.8%"))
    )
  }
}
