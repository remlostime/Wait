//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Logging
import Testing

@Suite struct LogTests {
  @Test func channelsShareTheSubsystem() {
    #expect(Log.subsystem == "com.chenkai.wait")
    #expect(Log.network.category == "network")
    #expect(Log.persistence.category == "persistence")
    #expect(Log.app.category == "app")
    Log.app.debug("LogTests smoke message")
  }
}
