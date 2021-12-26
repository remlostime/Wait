//
// Created by: kai_chen on 8/14/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Model
import SwiftUI

// MARK: - Checklist

struct Checklist: View {
  var item: ChecklistItem
  @State var showFullText: Bool = false
  var isTapped: (ChecklistItem) -> Void

  var body: some View {
    HStack {
      Button {
        isTapped(item)
        // item.isChecked.toggle()
      } label: {
        Image(systemName: item.isChecked ? "checkmark.square" : "square")
      }

      if item.isChecked {
        Text(item.name)
          .strikethrough()
          .onTapGesture {
            showFullText.toggle()
          }
      } else {
        Text(item.name)
          .onTapGesture {
            showFullText.toggle()
          }
      }
    }
    .sheet(isPresented: $showFullText, onDismiss: nil) {
      Text(item.name)
        .padding()
    }
  }
}

// MARK: - Checklist_Previews

struct Checklist_Previews: PreviewProvider {
  static var previews: some View {
    Checklist(item: ChecklistItem.example, isTapped: { _ in })
  }
}
