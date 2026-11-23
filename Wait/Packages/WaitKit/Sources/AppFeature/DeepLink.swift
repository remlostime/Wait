//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - DeepLink

/// `wait://stock/<SYMBOL>` (overview §9). It's used by widget rows and, in plan 06, by push notifications.
public enum DeepLink: Equatable, Sendable {
  case stock(String)

  // MARK: Lifecycle

  public init?(url: URL) {
    guard url.scheme?.lowercased() == "wait", url.host()?.lowercased() == "stock" else {
      return nil
    }
    let symbol = url.pathComponents.dropFirst().first?.uppercased() ?? ""
    // Letters and digits plus an exchange suffix: AAPL, BRK.B, 0700.HK.
    guard symbol.range(of: #"^[A-Z0-9]{1,10}([.-][A-Z0-9]{1,6})?$"#, options: .regularExpression) != nil else {
      return nil
    }
    self = .stock(symbol)
  }

  // MARK: Public

  public var url: URL {
    switch self {
      case let .stock(symbol): URL(string: "wait://stock/\(symbol)")!
    }
  }
}
