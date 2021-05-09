// Created by kai_chen on 5/9/21.

import SwiftUI

// MARK: - SearchBar

struct SearchBar: View {
  // MARK: Internal

  @Binding var keyword: String

  var body: some View {
    HStack {
      TextField("Search...", text: $keyword)
        .padding()
        .padding(.horizontal, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .padding(.horizontal, 10)
        .onTapGesture {
          self.isEditing = true
        }

      if isEditing {
        Button(action: {
          self.isEditing = false
          self.keyword = ""
        }, label: {
          Text("Cancel")
        })
          .padding(.trailing, 8)
          .transition(.move(edge: .trailing))
          .animation(.default)
      }
    }
  }

  // MARK: Private

  @State private var isEditing = false
}

// MARK: - SearchBar_Previews

struct SearchBar_Previews: PreviewProvider {
  static var previews: some View {
    SearchBar(keyword: .constant("Facebook"))
  }
}
