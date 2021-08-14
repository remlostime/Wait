// Created by kai_chen on 5/4/21.

import Alamofire
import Model
import Money
import PartialSheet
import Size
import SwiftUI
import SwiftyJSON

// MARK: - ContentView

struct ContentView: View {
  // MARK: Internal

  @State var stocks: [Stock]
  @State var stockRowDetailType: StockRowDetailType = .actionStatus
  @State var category: StockCategory = .waitlist
  @State var selection: String? = nil

  var stocksInCategory: [Stock] {
    stocks.filter { stock in
      stock.category == category
    }
  }

  var body: some View {
    NavigationView {
      VStack {
        Picker("Picker", selection: $category, content: {
          ForEach(StockCategory.allCases) { category in
            Text(category.description).tag(category)
          }
        })
          .pickerStyle(SegmentedPickerStyle())
          .padding(.all, 10)

        List {
          ForEach(stocksInCategory, id: \.symbol) { stock in
            HStack {
              StockRow(stockRowDetailType: $stockRowDetailType, stock: stock)

              // This is used to remove '>' in the cell
              // https://stackoverflow.com/questions/58333499/swiftui-navigationlink-hide-arrow
              // https://stackoverflow.com/questions/56516333/swiftui-navigationbutton-without-the-disclosure-indicator
              NavigationLink(destination: StockDetailsView(stock: stock), tag: stock.symbol, selection: $selection) {
                EmptyView()
              }
              .frame(width: 0)
              .opacity(0)
            }
          }
          .onDelete(perform: { indexSet in
            for index in indexSet {
              let stock = stocksInCategory[index]
              StockCache.shared.removeStock(stock)
              stocks.removeAll(where: {
                $0 == stock
              })
            }
          })
        }
        .id(UUID())
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

        networkClient.fetchStocks { result in
          switch result {
            case let .success(stocks):
              logger.verbose(stocks)
            case let .failure(error):
              logger.error("Failed to fetch stocks from server: \(error.localizedDescription)")
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

        networkClient.saveStock(stock)

        stocks.append(stock)
        saveStocks()
      }
    })
    .navigationViewStyle(StackNavigationViewStyle())
  }

  // MARK: Private

  private let networkClient = CloudNetworkClient.shared

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
    let stock = Stock.empty
    ContentView(stocks: [stock])
  }
}
