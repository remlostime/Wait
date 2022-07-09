//
// Created by: Kai Chen on 7/9/22.
// Copyright © 2021 Wait. All rights reserved.
//

import SwiftUI

// MARK: - ContentView

struct ContentView: View {
  var body: some View {
    VStack {
      Image(systemName: "globe")
        .imageScale(.large)
        .foregroundColor(.accentColor)
      Text("Hello, Kai!")
    }
  }
}

// MARK: - ContentView_Previews

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}
