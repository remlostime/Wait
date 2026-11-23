//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Persistence
import Testing

@Suite struct SnapshotStoreTests {
  func tempURL() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "snapshot-\(UUID().uuidString)/snapshot.json")
  }

  @Test func saveThenLoadRoundTrips() throws {
    let store = SnapshotStore.live(url: tempURL())
    let snapshot = WatchlistSnapshot(
      generatedAt: Date(timeIntervalSince1970: 1_795_186_800),
      quotesAsOf: nil,
      rows: [.init(symbol: "AAPL", name: "Apple", price: Decimal(string: "189.98"), changePercent: 1.2, status: .watch, temperature: 45, ladder: .empty, isFavorite: true)]
    )
    try store.save(snapshot)
    #expect(store.load() == snapshot)
  }

  @Test func missingOrCorruptFileLoadsNil() throws {
    let url = tempURL()
    #expect(SnapshotStore.live(url: url).load() == nil)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: url)
    #expect(SnapshotStore.live(url: url).load() == nil)
  }
}
