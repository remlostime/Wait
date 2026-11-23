//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import IdentifiedCollections
import Sharing

// Keys are declared on `SharedReaderKey`, as swift-sharing recommends. That makes them resolve for both `@Shared(.x)` and
// `@SharedReader(.x)`, because `SharedKey` refines `SharedReaderKey`. Declaring twins on `SharedKey` as well would make
// `@Shared(.watchlist)` ambiguous. Plan 05's `.syncState` follows the same pattern.

/// `@Shared(.watchlist)` lives in the app group, so the widget extension can read the same file.
public extension SharedReaderKey where Self == FileStorageKey<IdentifiedArrayOf<WatchlistItem>>.Default {
  static var watchlist: Self {
    Self[.fileStorage(AppGroup.fileURL(AppGroup.watchlistFileName)), default: []]
  }
}

/// `@Shared(.checklistTemplate)`: the prompts that seed every newly added stock.
public extension SharedReaderKey where Self == FileStorageKey<IdentifiedArrayOf<ChecklistItem>>.Default {
  static var checklistTemplate: Self {
    Self[
      .fileStorage(AppGroup.fileURL(AppGroup.checklistTemplateFileName)),
      default: IdentifiedArray(uniqueElements: ChecklistTemplate.defaultItems)
    ]
  }
}

// MARK: - Alerts (plan 06)

// Declared once, on `SharedReaderKey`, like `.watchlist` and `.syncState`, so `@Shared(.alertsEnabled)` isn't ambiguous.

/// `@Shared(.alertsEnabled)`: the user turned on "Daily alerts" in Settings.
public extension SharedReaderKey where Self == AppStorageKey<Bool>.Default {
  static var alertsEnabled: Self {
    Self[.appStorage("alerts.enabled"), default: false]
  }
}

/// `@Shared(.apnsDeviceToken)`: the APNs token (lowercase hex) last sent to `POST /api/devices`. Cleared only after the server confirms the DELETE.
public extension SharedReaderKey where Self == AppStorageKey<String?> {
  static var apnsDeviceToken: Self {
    .appStorage("apns.deviceToken")
  }
}
