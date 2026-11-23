//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Domain
import Foundation
import Observation

// MARK: - WatchSnapshotStore

/// The watch app's model: the latest `WatchlistSnapshot` the phone sent.
/// It lives in the package rather than the watch target so it can be unit-tested.
@MainActor
@Observable
public final class WatchSnapshotStore {
  // MARK: Lifecycle

  public init(connectivity: ConnectivityClient) {
    self.connectivity = connectivity
  }

  // MARK: Public

  public private(set) var snapshot: WatchlistSnapshot?

  public var favorites: [WatchlistSnapshot.Row] {
    snapshot?.rows.filter(\.isFavorite) ?? []
  }

  public var others: [WatchlistSnapshot.Row] {
    snapshot?.rows.filter { !$0.isFavorite } ?? []
  }

  public var isEmpty: Bool {
    snapshot?.rows.isEmpty ?? true
  }

  public func row(symbol: String) -> WatchlistSnapshot.Row? {
    snapshot?.rows.first { $0.symbol == symbol }
  }

  /// Activates the session, then applies snapshots until the stream ends. The live stream never ends,
  /// so call this from `.task` and let SwiftUI cancel it.
  public func start() async {
    await connectivity.activate()
    for await incoming in connectivity.snapshots() {
      apply(incoming)
    }
  }

  // MARK: Internal

  func apply(_ incoming: WatchlistSnapshot) {
    if let snapshot, incoming.generatedAt < snapshot.generatedAt {
      return
    }
    snapshot = incoming
  }

  // MARK: Private

  private let connectivity: ConnectivityClient
}
