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
      } label: {
        Image(systemName: item.isChecked ? "checkmark.square" : "square")
      }

      Text(item.name)
        .strikethrough(item.isChecked)
        .lineLimit(item.isChecked ? 1 : nil)

      Spacer()
    }
  }
}

// MARK: - Checklist_Previews

struct Checklist_Previews: PreviewProvider {
  static var previews: some View {
    Checklist(item: ChecklistItem.example, isTapped: { _ in })
  }
}
