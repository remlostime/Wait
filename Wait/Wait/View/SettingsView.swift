//
// Created by: kai_chen on 9/26/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Model
import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
  @AppStorage("stockRowStyle") var stockRowStyle: StockRowStyle = .card

  var body: some View {
    NavigationView {
      List {
        NavigationLink("Checklist") {
          ChecklistEditView(store: Store(
            initialState: ChecklistEditState(),
            reducer: settingsReducer,
            environment: ChecklistEditEnvironment()
          ))
        }

        Picker("Stock Row Style", selection: $stockRowStyle) {
          ForEach(StockRowStyle.allCases) { style in
            Text(style.rawValue).tag(style)
          }
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