// Created by kai_chen on 5/4/21.

import Alamofire
import Money
import PartialSheet
import SwiftUI
import SwiftyJSON

extension Binding {
  func onChange(_ handler: @escaping (Value) -> Void) -> Binding<Value> {
    Binding(
      get: { self.wrappedValue },
      set: { newValue in
        self.wrappedValue = newValue
        handler(newValue)
      }
    )
  }
}

// MARK: - StockRowDetailType

enum StockRowDetailType {
  case price
  case priceChange
  case actionStatus
}

// MARK: - ContentView

struct ContentView: View {
  // MARK: Internal

  @State var stocks: [Stock]
  @State var stockRowDetailType: StockRowDetailType = .price

  var body: some View {
    NavigationView {
      List(stocks, id: \.symbol) { stock in
        NavigationLink(destination: StockDetailsView(stock: stock)) {
          StockRow(stockRowDetailType: $stockRowDetailType, stock: stock)
        }
      }
      .navigationTitle("Waitlist")
      .listStyle(InsetListStyle())
      .toolbar(content: {
        Button(action: { showingWaitStockView.toggle() }, label: {
          Image(systemName: "plus")
        })
      })
      .sheet(isPresented: $showingWaitStockView, content: {
        NavigationView {
          SearchStockView(isPresented: $showingWaitStockView, stock: $newStock)
        }
        .accentColor(.avocado)
      })
    }
    .addPartialSheet(style: .defaultStyle())
    .onChange(of: newStock, perform: { value in
      fetchStockDetails(stock: value) { stock in
        stocks.append(stock)
        saveStocks()
      }
    })
  }

  func stockChanged(to value: Stock) {
    fetchStockDetails(stock: value) { stock in
      stocks.append(stock)
      saveStocks()
    }
  }

  // MARK: Private

  @State private var showingWaitStockView = false
  @State private var newStock = Stock(
    symbol: "FB",
    name: "Facebook",
    currentPrice: 1.0,
    expectedPrice: 1.0,
    changePercent: "1.8%"
  )

  private func saveStocks() {
    StockCache.shared.saveStocks(stocks)
  }

  private func buildStockQuoteURL(stock: Stock) -> URL? {
    let params = [
      "symbol": stock.symbol,
    ]

    let url = NetworkingURLBuilder.buildURL(api: "quote", params: params)

    return url
  }

  private func fetchStockDetails(stock: Stock, completion: @escaping ((Stock) -> Void)) {
    guard let url = buildStockQuoteURL(stock: stock) else {
      return
    }

    AF.request(url).validate().responseData { response in
      switch response.result {
        case let .success(data):
          let decoder = JSONDecoder()
          let dateFormatter = DateFormatter()
          dateFormatter.dateFormat = "yyyy-mm-dd"
          decoder.dateDecodingStrategy = .formatted(dateFormatter)

          guard
            let stockQuote = try? decoder.decode(StockCurrentQuote.self, from: data)
          else {
            logger.error("Failed to decode stock quote")
            return
          }

          // TODO(kai) - fix change percent
          let newStock = Stock(
            symbol: stockQuote.symbol,
            name: stock.name,
            currentPrice: stockQuote.close,
            expectedPrice: stock.expectedPrice,
            changePercent: ""
          )

          completion(newStock)
        case let .failure(error):
          logger.error("Failed to fetch stock quote: \(error.localizedDescription)")
      }
    }
  }
}

// MARK: - ContentView_Previews

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    let stock = Stock(
      symbol: "fb",
      name: "Facebook",
      currentPrice: 1.0,
      expectedPrice: 2.0,
      changePercent: "1.8%"
    )

    ContentView(stocks: [stock])
  }
}
