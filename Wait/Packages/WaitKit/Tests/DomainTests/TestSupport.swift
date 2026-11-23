//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation

/// Exact decimal from a string literal (never via Double).
func dec(_ string: String) -> Decimal {
  Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}

/// `2026-11-20T15:00:00Z`, a Friday at 10:00 ET when the market is open.
let fridayOpen = Date(timeIntervalSince1970: 1_795_186_800)
