// Created by kai_chen on 5/9/21.

import Alamofire
import Model
import Networking
import SwiftUI
import SwiftyJSON

// MARK: - SearchStockView

struct SearchStockView: View {
  @State private var keyword: String = ""
  @State private var searchStocks: [SearchStockResult] = []
  @Binding var isPresented: Bool
  @Binding var stock: Stock

  var body: some View {
    VStack {
      SearchBar(keyword: $keyword.onChange(keywordDidChange))

      List {
        ForEach(searchStocks, id: \.symbol) { searchStock in
          NavigationLink(destination: StockExpectedPriceInputView(searchStock: searchStock, stock: $stock, isPresented: $isPresented)) {
            SearchStockRow(stock: searchStock)
          }
        }
      }
    }
    .navigationTitle("Companies")
  }

  private func buildStockSearchURL(keyword: String) -> URL? {
    let params = [
      "symbol": keyword,
    ]

    let url = NetworkingURLBuilder.buildURL(api: "symbol_search", params: params)

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
            let rawData = try? json["data"].rawData(),
            let newSearchStocks = try? decoder.decode([SearchStockResult].self, from: rawData)
          else {
            logger.error("Failed to decode search stock")
            return
          }

          let acceptedExchange: Set<Exchange> = Set(Exchange.allCases)
          searchStocks = newSearchStocks.filter {
            guard let exchangeType = Exchange(rawValue: $0.exchange) else {
              return false
            }

            return acceptedExchange.contains(exchangeType)
          }
        case let .failure(error):
          logger.error("Failed to search stock: \(error.localizedDescription)")
      }
    }
  }

  func keywordDidChange(to newKeyword: String) {
    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
      guard newKeyword == keyword else {
        return
      }

      searchStocks(for: newKeyword)
    }
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
              changePercent: "1.8%",
              priceChartImage: nil))
    )
  }
}
