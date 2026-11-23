//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Connectivity
import Persistence

extension SnapshotClient {
  /// Returns a copy of this client whose `publish` first runs the original (the `snapshot.json` write
  /// and the widget reload), then sends the same snapshot to the watch.
  ///
  /// It lives in AppFeature so `Connectivity`, which the watch links, doesn't depend on `Persistence`.
  /// Watch delivery is best effort: `ConnectivityEngine` keeps the latest payload until a watch can take it,
  /// so an error here never fails publishing.
  func alsoSending(to connectivity: ConnectivityClient) -> SnapshotClient {
    let publishLocally = publish
    var client = self
    client.publish = { snapshot in
      await publishLocally(snapshot)
      try? await connectivity.send(snapshot)
    }
    return client
  }
}
