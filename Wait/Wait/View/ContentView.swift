// Created by kai_chen on 5/4/21.

import Alamofire
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

// MARK: - ContentView

struct ContentView: View {
  // MARK: Internal

  @State var stocks: [Stock]

  var body: some View {
    NavigationView {
      List(stocks, id: \.ticker) { stock in
        StockRow(stock: stock)
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
          WaitStockView(stock: $newStock.onChange(stockChanged), isPresented: $showingWaitStockView)
        }
      })
    }
  }

  func stockChanged(to value: Stock) {
    fetchStockDetails(stock: value) { stock in
      stocks.append(stock)
      saveStocks()
    }
  }

  // MARK: Private

  @State private var showingWaitStockView = false
  @State private var newStock = Stock(ticker: "FB", name: "Facebook", currentPrice: 1.0, expectedPrice: 1.0)

  private func saveStocks() {
    StockCache.shared.saveStocks(stocks)
  }

  private func buildStockQuoteURL(stock: Stock) -> URL? {
    guard let url = URL(string: "https://www.alphavantage.co/query") else {
      return nil
    }

    var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true)

    let functionItem = URLQueryItem(name: "function", value: "GLOBAL_QUOTE")
    let symbolItem = URLQueryItem(name: "symbol", value: stock.ticker)
    let apiKeyItem = URLQueryItem(name: "apikey", value: "L51Y2HE61NU1YU0G")

    urlComponents?.queryItems = [functionItem, symbolItem, apiKeyItem]

    return urlComponents?.url
  }

  private func fetchStockDetails(stock: Stock, completion: @escaping ((Stock) -> Void)) {
    guard let url = buildStockQuoteURL(stock: stock) else {
      return
    }

    AF.request(url).validate().responseData { response in
      switch response.result {
        case let .success(data):
          let decoder = JSONDecoder()

          guard
            let json = try? JSON(data: data),
            let rawData = try? json["Global Quote"].rawData(),
            let stockQuote = try? decoder.decode(StockQuote.self, from: rawData)
          else {
            logger.error("Failed to decode stock quote")
            return
          }

          let newStock = Stock(ticker: stockQuote.symbol, name: "haha", currentPrice: Double(stockQuote.price) ?? 0.0, expectedPrice: stock.expectedPrice)

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
      ticker: "fb",
      name: "Facebook",
      currentPrice: 1.0,
      expectedPrice: 2.0
    )

    ContentView(stocks: [stock])
  }
}