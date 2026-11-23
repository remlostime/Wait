//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - NotificationPayload

/// Reads the stock symbol out of an alert push (`{"symbol": "AAPL", "deepLink": "wait://stock/AAPL", …}`, overview §8.7).
public enum NotificationPayload {
  // MARK: Public

  public static func symbol(from userInfo: [AnyHashable: Any]) -> String? {
    if let raw = userInfo["symbol"] as? String, let symbol = normalized(raw) {
      return symbol
    }
    guard
      let link = userInfo["deepLink"] as? String,
      let url = URL(string: link),
      url.scheme == "wait",
      url.host() == "stock",
      let raw = url.pathComponents.dropFirst().first
    else {
      return nil
    }
    return normalized(raw)
  }

  // MARK: Private

  /// Same rule as plan 02's `DeepLink` (`^[A-Z0-9]{1,10}([.-][A-Z0-9]{1,6})?$`), so every symbol the app can open is accepted.
  private static func normalized(_ raw: String) -> String? {
    let symbol = raw.uppercased()
    return symbol.range(of: #"^[A-Z0-9]{1,10}([.-][A-Z0-9]{1,6})?$"#, options: .regularExpression) == nil ? nil : symbol
  }
}
