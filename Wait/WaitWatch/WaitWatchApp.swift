//
// Created by: Kai Chen on 7/9/22.
// Copyright © 2021 Wait. All rights reserved.
//

import Connectivity
import SwiftUI

// MARK: - WaitWatchApp

@main
struct WaitWatchApp: App {
  // MARK: Internal

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        WatchlistListView(store: store)
      }
      .task {
        await store.start()
      }
    }
  }

  // MARK: Private

  @State private var store = WatchSnapshotStore(connectivity: .liveValue)
}
