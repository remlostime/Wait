//
// Created by: kai_chen on 9/26/21.
// Copyright © 2021 Wait. All rights reserved.
//

import SwiftUI

struct SettingsView: View {
  var body: some View {
    NavigationView {
      VStack {
        NavigationLink("Checklist") {
          Text("Hello world")
        }
      }
      .navigationTitle("Settings")
    }
  }
}

struct SettingsView_Previews: PreviewProvider {
  static var previews: some View {
    SettingsView()
  }
}
