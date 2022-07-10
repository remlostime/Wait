//
// Created by: Kai Chen on 7/10/22.
// Copyright © 2021 Wait. All rights reserved.
//

import SwiftUI

// MARK: - StockRowDetailType

enum StockRowDetailType: String, CaseIterable {
  case price = "Price"
  case priceChange = "Price Change"
  case actionStatus = "Action Status"
}

// MARK: Identifiable

extension StockRowDetailType: Identifiable {
  var id: Self {
    self
  }
}

struct StockTypeSwitchRow: View {
  
  @Binding var stockRowDetailType: StockRowDetailType
  @State var showDisplaySheet: Bool = false
  
  init(stockRowDetailType: Binding<StockRowDetailType>) {
    _stockRowDetailType = stockRowDetailType
  }
  
  var body: some View {
    VStack(alignment: .leading) {
      Text("Viewing")
        .font(.title3)
      Text("\(stockRowDetailType.rawValue)")
        .font(.subheadline)
        .foregroundColor(.secondary)
    }
    .onTapGesture {
      showDisplaySheet.toggle()
    }
    .confirmationDialog("Display Data", isPresented: $showDisplaySheet, titleVisibility: .automatic, actions: {
      ForEach(StockRowDetailType.allCases) { type in
        Button(type.rawValue) {
          stockRowDetailType = type
        }
      }

      Button("Cancel", role: .cancel) {
        showDisplaySheet = false
      }
    })
  }
}

struct StockTypeSwitchRow_Previews: PreviewProvider {
  static var previews: some View {
    StockTypeSwitchRow(stockRowDetailType: .constant(.price))
  }
}
