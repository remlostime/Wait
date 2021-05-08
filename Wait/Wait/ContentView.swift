// Created by kai_chen on 5/4/21.

import SwiftUI

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

  var stocks: [Stock]

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
//          WaitStockView(stock: $stock, .constant("FB"), isPresented: .constant("100"), ticker: $showingWaitStockView)
          WaitStockView(stock: $newStock.onChange(stockChanged), isPresented: $showingWaitStockView, ticker: .constant("fb"), price: .constant("1.0"))
        }
      })
    }
  }

  func stockChanged(to value: Stock?) {
    guard let value = value else {
      return
    }

    print(value)

//    stocks.append(value)
  }

  // MARK: Private

  @State private var showingWaitStockView = false
  @State private var newStock: Stock?
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
