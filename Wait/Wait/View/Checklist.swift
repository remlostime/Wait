//
// Created by: kai_chen on 8/14/21.
// Copyright © 2021 Wait. All rights reserved.
//

import SwiftUI
import Model

struct Checklist: View {
  @State var isChecked: Bool = false

  var item: ChecklistItem

  var body: some View {
    HStack {
      Button {
        isChecked = !isChecked
      } label: {
        Image(systemName: isChecked ? "checkmark.square" : "square")
      }

      // TODO(kai) - Add preview all text feature
      if isChecked {
        Text(item.name)
          .strikethrough()
      } else {
        Text(item.name)
      }
    }
  }
}

struct Checklist_Previews: PreviewProvider {
  static var previews: some View {
    Checklist(item: ChecklistItem.example)
  }
}
