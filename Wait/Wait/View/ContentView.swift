// Created by kai_chen on 5/4/21.

import Alamofire
import Color
import Logging
import Model
import Money
import PartialSheet
import Size
import SwiftUI
import SwiftyJSON

// MARK: - ContentView

struct ContentView: View {
  // MARK: Internal

  @State var stockRowDetailType: StockRowDetailType = .actionStatus
  @State var category: StockCategory = .waitlist
  @State var selection: String? = nil

  @AppStorage("stockRowStyle") var stockRowStyle: StockRowStyle = .card

  var stocks: [Stock] {
    dataSource.stocks
  }

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

        switch stockRowStyle {
          case .card:
            ScrollView {
              LazyVGrid(
                columns: [
                  GridItem(.adaptive(minimum: 150, maximum: 170)),
                  GridItem(.adaptive(minimum: 150, maximum: 170))],
                spacing: 16
              ) {
                ForEach(stocksInCategory, id: \.symbol) { stock in
                  NavigationLink {
                    StockDetailsView(stock: stock)
                  } label: {
                    StockCard(stock: stock)
                  }
                }
              }
            }
          case .row:
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
              .onMove { source, dst in
                dataSource.moveStock(fromOffset: source, toOffset: dst)
              }
              .onDelete(perform: { indexSet in
                for index in indexSet {
                  let stock = stocksInCategory[index]
                  dataSource.removeStock(stock)
                }
              })
             }
             .id(UUID())
        }
      }
      .onAppear {
        dataSource.fetchStocks()

        // iCloud fetch
        /*
         networkClient.fetchStocks { result in
           switch result {
             case let .success(stocks):
               logger.verbose(stocks)
             case let .failure(error):
               logger.error("Failed to fetch stocks from server: \(error.localizedDescription)")
           }
         }
         */
      }
      .navigationTitle("Wait")
      .listStyle(InsetListStyle())
      .toolbar(content: {
        HStack {
          EditButton()

          Spacer(minLength: Size.horizontalPadding16)

          Button(action: { showingWaitStockView.toggle() }, label: {
            Image(systemName: "plus")
          })
        }
      })
      .sheet(isPresented: $showingWaitStockView, content: {
        NavigationView {
          SearchStockView(isPresented: $showingWaitStockView, stock: $newStock)
        }
        .accentColor(Color.mint)
      })
    }
    .addPartialSheet(style: .defaultStyle())
    .onChange(of: newStock, perform: { value in
      dataSource.fetchStock(value)
    })
    .navigationViewStyle(StackNavigationViewStyle())
  }

  // MARK: Private

  @ObservedObject private var dataSource = StockCurrentQuoteDataSource()

  private let networkClient = CloudNetworkClient.shared

  private let stockCurrentQuoteNetworkClient = StockCurrentQuoteNetworkClient()

  @State private var showingWaitStockView = false
  @State private var newStock = Stock.empty
}

// MARK: - ContentView_Previews

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}
