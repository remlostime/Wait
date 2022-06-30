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
    NavigationStack {
      VStack {
        Picker("Stock Row Style", selection: $stockRowStyle) {
          ForEach(StockRowStyle.allCases) { style in
            Text(style.rawValue).tag(style)
          }
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding([.leading, .trailing], Size.horizontalPadding24)

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
            List(stocks) { stock in
              NavigationLink(value: stock) {
                StockRow(stockRowDetailType: $stockRowDetailType, stock: stock)
              }
            }
            .navigationDestination(for: Stock.self) { stock in
              StockDetailsView(stock: stock)
            }
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
          .accentColor(.mint)
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
