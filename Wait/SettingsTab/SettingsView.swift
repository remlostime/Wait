//
// Created by: kai_chen on 9/26/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ChecklistEditFeature
import ComposableArchitecture
import Model
import SwiftUI

// MARK: - SettingsView

public struct SettingsView: View {
  @AppStorage("stockRowStyle") var stockRowStyle: StockRowStyle = .card

  public init() {}

  public var body: some View {
    NavigationView {
      List {
        NavigationLink("Checklist") {
          ChecklistEditView(store: Store(
            initialState: ChecklistEditState(items: []),
            reducer: ChecklistEditReducerBuilder.build(),
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
