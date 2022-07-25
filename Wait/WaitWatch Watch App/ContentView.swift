//
// Created by: Kai Chen on 7/9/22.
// Copyright © 2021 Wait. All rights reserved.
//

import SwiftUI

// MARK: - ContentView

struct ContentView: View {
  // MARK: Internal

  @State var stockRowDetailType: StockRowDetailType = .price

  var body: some View {
    List(dataSource.stocks) { stock in
      StockRow(stockRowDetailType: $stockRowDetailType, stock: stock)
    }
    .onAppear {
      dataSource.fetchStocks()
    }

    /*
     List(1 ..< 10) { item in
       if item == 1 {
         StockTypeSwitchRow(stockRowDetailType: $stockRowDetailType)
       } else {

       }
     }
      */
  }

  // MARK: Private

  @ObservedObject private var dataSource = StockCurrentQuoteDataSource()
}

// MARK: - ContentView_Previews

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}
