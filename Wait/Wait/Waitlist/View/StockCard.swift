//
// Created by: kai_chen on 10/16/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Model
import Size
import SwiftUI

// MARK: - StockCard

struct StockCard: View {
  var stock: Stock

  var body: some View {
    VStack(alignment: .leading) {
      Text(stock.tradeAction.rawValue)
        .padding(EdgeInsets(top: Size.verticalPadding4, leading: Size.horizontalPadding8, bottom: Size.verticalPadding4, trailing: Size.horizontalPadding8))
        .background(stock.actionColor)
        .cornerRadius(5.0)
        .font(.subheadline)
        .foregroundColor(.white)

      Text(stock.symbol)
        .font(.title3)
        .foregroundColor(.primary)
      Text(stock.name)
        .font(.subheadline)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.leading)

      Spacer(minLength: Size.verticalPadding32)

      Text(stock.currentPrice.formattedCurrency)
        .foregroundColor(stock.priceColor)
        .font(.subheadline)
      Text(stock.formattedChangePercent)
        .foregroundColor(stock.priceColor)
        .font(.caption)
    }
    .padding()
    .frame(width: 140, height: 180, alignment: .leading)
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(Color(.sRGB, red: 150 / 255, green: 150 / 255, blue: 150 / 255, opacity: 0.1), lineWidth: 1)
    )
    .shadow(color: Color(red: 0, green: 0, blue: 0, opacity: 0.16), radius: 16, x: 0, y: 7)
  }
}

// MARK: - StockCard_Previews

struct StockCard_Previews: PreviewProvider {
  static var previews: some View {
    StockCard(stock: .empty)
  }
}
