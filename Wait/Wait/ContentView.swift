// Created by kai_chen on 5/4/21.

import SwiftUI

struct ContentView: View {

  let stocks: [Stock]

  @State private var showingWaitStockView = false

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
          WaitStockView(ticker: .constant("FB"), price: .constant("100"))
        }
      })
    }

  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    let stock = Stock(
      ticker: "fb",
      name: "Facebook",
      currentPrice: 1.0,
      expectedPrice: 2.0)

    ContentView(stocks: [stock])
  }
}
