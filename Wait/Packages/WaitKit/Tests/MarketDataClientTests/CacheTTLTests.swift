//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import MarketDataClient
import Testing

@Suite struct CacheTTLTests {
  let open = Date(timeIntervalSince1970: 1_795_186_800) // Fri 2026-11-20 10:00 ET
  let postClose = Date(timeIntervalSince1970: 1_795_209_000) // Fri 16:10 ET
  let evening = Date(timeIntervalSince1970: 1_795_212_000) // Fri 17:00 ET
  let saturday = Date(timeIntervalSince1970: 1_795_273_200) // Sat 10:00 ET
  let mondayOpen = Date(timeIntervalSince1970: 1_795_444_200) // Mon 2026-11-23 09:30 ET

  @Test func quotes() {
    #expect(CacheTTL.expiry(for: .quote, fetchedAt: open) == open + 60)
    #expect(CacheTTL.expiry(for: .quote, fetchedAt: postClose) == postClose + 300)
    #expect(CacheTTL.expiry(for: .quote, fetchedAt: evening) == mondayOpen)
    #expect(CacheTTL.expiry(for: .quote, fetchedAt: saturday) == mondayOpen)
  }

  @Test func intradaySeries() {
    #expect(CacheTTL.expiry(for: .series(.oneDay), fetchedAt: open) == open + 300)
    #expect(CacheTTL.expiry(for: .series(.oneDay), fetchedAt: evening) == mondayOpen)
    #expect(CacheTTL.expiry(for: .series(.oneWeek), fetchedAt: open) == open + 900)
    #expect(CacheTTL.expiry(for: .series(.oneWeek), fetchedAt: saturday) == mondayOpen)
  }

  @Test func dailySeriesExpireTwoHoursAfterTheNextClose() {
    #expect(CacheTTL.expiry(for: .series(.oneYear), fetchedAt: open) == Date(timeIntervalSince1970: 1_795_215_600)) // Fri 18:00 ET
    #expect(CacheTTL.expiry(for: .series(.fiveYears), fetchedAt: evening) == Date(timeIntervalSince1970: 1_795_474_800)) // Mon 18:00 ET
    #expect(CacheTTL.expiry(for: .series(.oneMonth), fetchedAt: open) == Date(timeIntervalSince1970: 1_795_215_600))
  }

  @Test func weekdayPreOpenWaitsForTheOpen() {
    let preOpen = Date(timeIntervalSince1970: 1_795_438_800) // Mon 2026-11-23 08:00 ET
    #expect(CacheTTL.expiry(for: .quote, fetchedAt: preOpen) == mondayOpen)
    #expect(CacheTTL.expiry(for: .series(.oneDay), fetchedAt: preOpen) == mondayOpen)
    #expect(CacheTTL.expiry(for: .series(.oneYear), fetchedAt: preOpen) == Date(timeIntervalSince1970: 1_795_474_800)) // Mon 18:00 ET
  }

  @Test func searchAndProfile() {
    #expect(CacheTTL.expiry(for: .search, fetchedAt: open) == open + 86400)
    #expect(CacheTTL.expiry(for: .profile, fetchedAt: open) == open + 7 * 86400)
    #expect(CacheTTL.maxStaleAge == 7 * 86400)
  }
}
