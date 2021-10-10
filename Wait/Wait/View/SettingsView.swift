//
// Created by: kai_chen on 9/26/21.
// Copyright © 2021 Wait. All rights reserved.
//

import SwiftUI
import ComposableArchitecture

// MARK: - SettingsView

struct SettingsView: View {
  var body: some View {
    NavigationView {
      List {
        NavigationLink("Checklist") {
          ChecklistEditView(store: Store(
            initialState: ChecklistEditState(),
            reducer: settingsReducer,
            environment: ChecklistEditEnvironment()))
        }
      }
      .navigationTitle("Settings")
    }
  }
}

// MARK: - SettingsView_Previews

struct SettingsView_Previews: PreviewProvider {
  static var previews: some View {
    SettingsView()
  }
}
