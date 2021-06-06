//
// Created by: kai_chen on 6/6/21.
// Copyright © 2021 Wait. All rights reserved.
//

import SwiftUI

struct StockStatsView: View {
  var title: String
  var value: String

  var body: some View {
    HStack {
      Text(title)
        .foregroundColor(.gray)
      Spacer()
      Text(value)
    }
  }
}

struct StockStatsView_Previews: PreviewProvider {
  static var previews: some View {
    StockStatsView(title: "Open", value: "143.2")
  }
}
