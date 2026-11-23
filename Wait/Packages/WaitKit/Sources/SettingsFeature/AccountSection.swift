//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import SwiftUI

// MARK: - AccountSection

struct AccountSection: View {
  let store: StoreOf<SettingsFeature>

  var body: some View {
    Section {
      LabeledContent("Anonymous ID") {
        Text(store.account.anonymousID ?? "Created on next sync")
          .font(.footnote.monospaced())
          .lineLimit(1)
          .truncationMode(.middle)
          .textSelection(.enabled)
      }
      Button(role: .destructive) {
        store.send(.deleteAccountTapped)
      } label: {
        if store.account.isDeleting {
          ProgressView()
        } else {
          Text("Delete Account")
        }
      }
      .disabled(store.account.isDeleting)
      if let message = store.account.errorMessage {
        Text(message).font(.footnote).foregroundStyle(.red)
      }
    } header: {
      Text("Account")
    } footer: {
      Text("Your anonymous ID is kept in iCloud Keychain, so your devices share one watchlist. Deleting the account removes your data from the Wait server only.")
    }
  }
}
