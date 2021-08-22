//
// Created by: kai_chen on 8/22/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Model
import Size
import SwiftUI

// MARK: - WidgetStockRow

struct WidgetStockRow: View {
  // MARK: Internal

  var stock: Stock

  var body: some View {
    HStack {
      Text(stock.symbol)

      Spacer()

      Text(buttonText)
        .padding(EdgeInsets(top: Size.verticalPadding4, leading: Size.horizontalPadding4, bottom: Size.verticalPadding4, trailing: Size.horizontalPadding4))
        .background(stock.actionColor)
        .cornerRadius(5.0)
    }
  }

  // MARK: Private

  private var buttonText: String {
    stock.tradeAction.rawValue
  }
}

// MARK: - WidgetStockRow_Previews

struct WidgetStockRow_Previews: PreviewProvider {
  static var previews: some View {
    WidgetStockRow(stock: Stock.empty)
  }
}
