//
// Created by: kai_chen on 12/6/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Model
import Size
import SwiftUI

// MARK: - ChecklistCardView

struct ChecklistCardView: View {
  // MARK: Internal

  @Binding var checklistItem: ChecklistItem

  var didTap: (Bool) -> Void

  var body: some View {
    ZStack {
      VStack(alignment: .center, spacing: 20) {
        Text(checklistItem.name)
          .font(.largeTitle)
          .minimumScaleFactor(0.2)
          .allowsTightening(true)
          .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
          .animation(.easeInOut)
        HStack(spacing: Size.horizontalPadding32) {
          Button(action: { didTap(false) }) {
            Image(systemName: "multiply")
          }
          Button(action: { didTap(true) }) {
            Image(systemName: "checkmark")
          }
        }
        Image(systemName: checklistItem.isChecked ? "checkmark.circle.fill" : "checkmark.circle")
      }
      .frame(width: min(300, bounds.width * 0.7), height: min(400, bounds.height * 0.6))
      .padding(20)
      .cornerRadius(20)
    }
  }

  // MARK: Private

  private var bounds: CGRect { UIScreen.main.bounds }
}

// MARK: - ChecklistCardView_Previews

struct ChecklistCardView_Previews: PreviewProvider {
  static var previews: some View {
    ChecklistCardView(checklistItem: .constant(ChecklistItem.example), didTap: { _ in })
      .previewLayout(.sizeThatFits)
  }
}
