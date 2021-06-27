// Created by kai_chen on 5/4/21.

import Alamofire
import Model
import Money
import PartialSheet
import SwiftUI
import SwiftyJSON

// MARK: - ContentView

struct ContentView: View {
  // MARK: Internal

  @State var stocks: [Stock]
  @State var stockRowDetailType: StockRowDetailType = .price

  var body: some View {
    NavigationView {
      List(stocks, id: \.symbol) { stock in
        HStack {
          StockRow(stockRowDetailType: $stockRowDetailType, stock: stock)

          // This is used to remove '>' in the cell
          // https://stackoverflow.com/questions/58333499/swiftui-navigationlink-hide-arrow
          // https://stackoverflow.com/questions/56516333/swiftui-navigationbutton-without-the-disclosure-indicator
          NavigationLink(destination: StockDetailsView(stock: stock)) {
            EmptyView()
          }
          .frame(width: 0)
          .opacity(0)
        }
      }
      .onAppear {
        stocks = StockCache.shared.getStocks()
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
        .accentColor(.mint)
      })
    }
    .addPartialSheet(style: .defaultStyle())
    .onChange(of: newStock, perform: { value in
      stockCurrentQuoteNetworkClient.fetchStockDetails(stock: value) { stock in
        stocks.append(stock)
        saveStocks()
      }
    })
  }

  func stockChanged(to value: Stock) {
    stockCurrentQuoteNetworkClient.fetchStockDetails(stock: value) { stock in
      stocks.append(stock)
      saveStocks()
    }
  }

  // MARK: Private

  private let stockCurrentQuoteNetworkClient = StockCurrentQuoteNetworkClient()

  @State private var showingWaitStockView = false
  @State private var newStock = Stock(
    symbol: "FB",
    name: "Facebook",
    currentPrice: 1.0,
    expectedPrice: 1.0,
    changePercent: "1.8%",
    priceChartImage: nil
  )

  private func saveStocks() {
    StockCache.shared.saveStocks(stocks)
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
      changePercent: "1.8%",
      priceChartImage: nil
    )

    ContentView(stocks: [stock])
  }
}
