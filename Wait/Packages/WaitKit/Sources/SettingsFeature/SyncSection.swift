//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import SwiftUI

// MARK: - SyncSection

struct SyncSection: View {
  // MARK: Internal

  let lastSyncedAt: Date?
  let isSyncing: Bool
  let errorMessage: String?
  let onSyncNow: () -> Void

  var body: some View {
    Section {
      LabeledContent("Last synced") {
        if let lastSyncedAt {
          Text(lastSyncedAt, format: .relative(presentation: .named))
        } else {
          Text("Never")
        }
      }

      Button(action: onSyncNow) {
        HStack {
          Text("Sync now")
          Spacer()
          if isSyncing {
            ProgressView()
          }
        }
      }
      .disabled(isSyncing)

      if let errorMessage {
        Text(errorMessage)
          .font(.footnote)
          .foregroundStyle(.red)
      }
    } header: {
      Text("Sync")
    } footer: {
      Text("Your watchlist syncs when Wait opens, after each change, and when you pull to refresh.")
    }
  }
}

#Preview {
  Form {
    SyncSection(lastSyncedAt: .now.addingTimeInterval(-120), isSyncing: false, errorMessage: nil, onSyncNow: {})
    SyncSection(lastSyncedAt: nil, isSyncing: true, errorMessage: "The Internet connection appears to be offline.", onSyncNow: {})
  }
}
