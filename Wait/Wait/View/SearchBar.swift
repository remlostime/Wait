// Created by kai_chen on 5/9/21.

import SwiftUI

struct SearchBar: View {
  @Binding var keyword: String
  @State private var isEditing = false

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
}

struct SearchBar_Previews: PreviewProvider {
  static var previews: some View {
    SearchBar(keyword: .constant("Facebook"))
  }
}
