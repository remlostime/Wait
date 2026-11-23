//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import SwiftUI

// MARK: - AlertsSection

struct AlertsSection: View {
  // MARK: Internal

  let store: StoreOf<SettingsFeature>

  var body: some View {
    Section {
      Toggle("Daily alerts", isOn: alertsBinding)
      if store.showsOpenSystemSettings {
        VStack(alignment: .leading, spacing: 4) {
          Text("Notifications are turned off for Wait.")
            .font(.footnote)
            .foregroundStyle(.secondary)
          Button("Open Settings") {
            store.send(.openSystemSettingsTapped)
          }
        }
      }
    } header: {
      Text("Alerts")
    } footer: {
      Text("After the US close on trading days, Wait checks each stock's ladder and notifies you when the price drops into a buy zone or rises to trim or sell.")
    }
  }

  // MARK: Private

  private var alertsBinding: Binding<Bool> {
    Binding(
      get: { store.alertsEnabled },
      set: { store.send(.alertsToggled($0)) }
    )
  }
}
