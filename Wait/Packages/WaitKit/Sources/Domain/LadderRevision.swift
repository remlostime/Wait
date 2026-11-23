//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

// MARK: - LadderRevision

/// One entry in a stock's ladder history, recorded each time the user saves a changed ladder.
public struct LadderRevision: Codable, Equatable, Sendable {
  // MARK: Lifecycle

  /// `date` is truncated to milliseconds (overview D21).
  public init(date: Date, ladder: PriceLadder) {
    self.date = date.truncatedToMilliseconds
    self.ladder = ladder
  }

  // MARK: Public

  public static let maxCount = 200

  public var date: Date
  public var ladder: PriceLadder
}
