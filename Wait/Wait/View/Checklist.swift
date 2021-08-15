//
// Created by: kai_chen on 8/14/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Model
import SwiftUI

// MARK: - Checklist

struct Checklist: View {
  @State var isChecked: Bool = false

  var item: ChecklistItem
  @State var showFullText: Bool = false

  // TODO(kai) - It should have a better way to update this var from its parent
  @Binding var checkedItemCounts: Int

  var body: some View {
    HStack {
      Button {
        isChecked.toggle()
        if isChecked {
          checkedItemCounts += 1
        } else {
          checkedItemCounts -= 1
        }
      } label: {
        Image(systemName: isChecked ? "checkmark.square" : "square")
      }

      if isChecked {
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
    .partialSheet(isPresented: $showFullText) {
      Text(item.name)
        .padding()
    }
  }
}

// MARK: - Checklist_Previews

struct Checklist_Previews: PreviewProvider {
  static var previews: some View {
    Checklist(item: ChecklistItem.example, checkedItemCounts: .constant(1))
  }
}
