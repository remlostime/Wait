// Created by kai_chen on 5/4/21.

import Alamofire
import Color
import Logging
import Model
import Money
import Networking
import Size
import StockDetailsFeature
import SwiftUI

// MARK: - MainView

public struct MainView: View {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  public var body: some View {
    NavigationView {
      VStack {
        switch stockRowStyle {
          case .card:
            ScrollView {
              LazyVGrid(
                columns: [
                  GridItem(.adaptive(minimum: 150, maximum: 170)),
                  GridItem(.adaptive(minimum: 150, maximum: 170)),
                ],
                spacing: 16
              ) {
                ForEach(stocks, id: \.symbol) { stock in
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
              ForEach(stocks, id: \.symbol) { stock in
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
                  let stock = stocks[index]
                  dataSource.removeStock(stock)
                }
              })
            }
            .id(UUID())
        }
      }
      .onAppear {
        dataSource.fetchStocks()
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
        SearchStockView(isPresented: $showingWaitStockView, stock: $newStock)
          .accentColor(Color(UIColor.mint))
      })
    }
    .onChange(of: newStock, perform: { value in
      dataSource.fetchStock(value)
    })
    .navigationViewStyle(StackNavigationViewStyle())
  }

  // MARK: Internal

  @State var stockRowDetailType: StockRowDetailType = .actionStatus
  @State var selection: String? = nil

  @AppStorage("stockRowStyle") var stockRowStyle: StockRowStyle = .card

  var stocks: [Stock] {
    dataSource.stocks
  }

  // MARK: Private

  @ObservedObject private var dataSource = StockCurrentQuoteDataSource()

  private let stockCurrentQuoteNetworkClient = StockCurrentQuoteNetworkClient()

  @State private var showingWaitStockView = false
  @State private var newStock = Stock.empty
}

// MARK: - ContentView_Previews

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    MainView()
  }
}
