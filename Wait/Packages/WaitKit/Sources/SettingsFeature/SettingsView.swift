//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ChecklistFeature
import ComposableArchitecture
import DesignSystem
import SwiftUI

// MARK: - SettingsView

public struct SettingsView: View {
  // MARK: Lifecycle

  public init(store: StoreOf<SettingsFeature>) {
    self.store = store
  }

  // MARK: Public

  public var body: some View {
    NavigationStack(path: $store.scope(\.path, action: \.path)) {
      Form {
        Section("Checklist") {
          Button {
            store.send(.checklistTemplateTapped)
          } label: {
            LabeledContent {
              Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            } label: {
              Label("Checklist template", systemImage: "checklist")
            }
          }
          .foregroundStyle(.primary)
        }
        Section {
          LabeledContent("Version", value: store.appVersion)
        } header: {
          Text("About")
        } footer: {
          Text("Data: Twelve Data (temporary). Prices may be delayed. Not investment advice.")
        }
      }
      .navigationTitle("Settings")
    } destination: { store in
      switch store.case {
        case let .checklistTemplate(templateStore):
          ChecklistTemplateView(store: templateStore)
      }
    }
  }

  // MARK: Private

  @Bindable private var store: StoreOf<SettingsFeature>
}

#Preview {
  SettingsView(store: Store(initialState: SettingsFeature.State()) { SettingsFeature() })
}
