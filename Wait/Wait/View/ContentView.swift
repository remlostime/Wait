// Created by kai_chen on 5/4/21.

import Alamofire
import Model
import Money
import PartialSheet
import SwiftUI
import SwiftyJSON
import Size

// MARK: - ContentView

struct ContentView: View {
  // MARK: Internal

  @State var stocks: [Stock]
  @State var stockRowDetailType: StockRowDetailType = .actionStatus

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
        StockCache.shared.getStocks { stocks in
          let group = DispatchGroup()
          var updatedStocks = stocks

          for (index, stock) in stocks.enumerated() {
            group.enter()
            stockCurrentQuoteNetworkClient.fetchStockDetails(stock: stock) { stock in
              if let stock = stock {
                updatedStocks[index] = stock
              }

              group.leave()
            }
          }

          group.notify(queue: DispatchQueue.main) {
            self.stocks = updatedStocks
          }
        }
      }
      .onDisappear {
        saveStocks()
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
        guard let stock = stock else {
          return
        }

        stocks.append(stock)
        saveStocks()
      }
    })
  }

  // MARK: Private

  private let stockCurrentQuoteNetworkClient = StockCurrentQuoteNetworkClient()

  @State private var showingWaitStockView = false
  @State private var newStock = Stock.empty

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
