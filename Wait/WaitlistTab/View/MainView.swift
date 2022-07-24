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
        ScrollView {
          LazyVGrid(
            columns: [
              GridItem(.adaptive(minimum: 150, maximum: 400)),
              GridItem(.adaptive(minimum: 150, maximum: 400)),
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

  @State var selection: String? = nil

  var stocks: [Stock] {
    dataSource.stocks
  }

  // MARK: Private

  @ObservedObject private var dataSource = StockCurrentQuoteDataSource()

  @State private var showingWaitStockView = false
  @State private var newStock = Stock.empty
}

// MARK: - ContentView_Previews

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    MainView()
  }
}
