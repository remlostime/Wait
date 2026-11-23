//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - TwelveDataAPIKey

public enum TwelveDataAPIKey {
  public static let placeholder = "replace-with-your-twelve-data-key"

  /// False for a missing, empty or whitespace-only key, an unexpanded build setting such as `$(TWELVE_DATA_API_KEY)`, and the placeholder.
  public static func isUsable(_ key: String?) -> Bool {
    guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
      return false
    }
    return !key.hasPrefix("$(") && key != placeholder
  }
}
