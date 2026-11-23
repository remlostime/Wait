//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Connectivity
import Domain
import Foundation
import Logging
import Persistence
import SettingsFeature
import SwiftUI
import SyncClient
import WatchlistFeature

// MARK: - AppFeature

@Reducer
public struct AppFeature {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  public enum Tab: Hashable, Sendable {
    case watchlist
    case settings
  }

  @ObservableState
  public struct State: Equatable {
    public init() {}

    public var selectedTab: Tab = .watchlist
    public var watchlist = WatchlistFeature.State()
    public var settings = SettingsFeature.State()
  }

  public enum Action: BindableAction {
    case binding(BindingAction<State>)
    case scenePhaseChanged(ScenePhase)
    case openURL(URL)
    case appDelegate(AppDelegateAction)
    case watchlist(WatchlistFeature.Action)
    case settings(SettingsFeature.Action)
    case syncFinished(SyncReport)
    case syncFailed(String)
  }

  public enum CancelID: Hashable, Sendable {
    case publishSnapshot
    case sync
  }

  public var body: some ReducerOf<Self> {
    CombineReducers {
      BindingReducer()
      Scope(\.watchlist, action: \.watchlist) {
        WatchlistFeature()
      }
      Scope(\.settings, action: \.settings) {
        SettingsFeature()
      }
      Reduce { state, action in
        switch action {
          case .appDelegate(.didFinishLaunching):
            // Publish once on launch, so the widget has data even before any quote changes.
            return .merge(
              publishSnapshot(state.watchlist.snapshotInputs),
              .run { [connectivity] _ in await connectivity.activate() }
            )

          case let .scenePhaseChanged(phase):
            switch phase {
              case .active:
                return .merge(.send(.watchlist(.sceneBecameActive)), sync(after: nil))
              case .background:
                // `@Shared(.fileStorage)` throttles writes, so flush them before the app is suspended (overview risk 5).
                // The snapshot is published at once, because the debounce might never fire in a suspended app. Starting it also cancels
                // the pending debounced publish (`cancelInFlight`).
                @Shared(.checklistTemplate) var template
                return .merge(
                  publishSnapshot(state.watchlist.snapshotInputs, debounced: false),
                  .run { [items = state.watchlist.$items, template = $template] _ in
                    // Separate `do`/`catch` blocks, so a failed items save doesn't skip the template save and never reaches `reportIssue`.
                    do {
                      try await items.save()
                    } catch {
                      Log.persistence.error("Saving the watchlist on background failed: \(error)")
                    }
                    do {
                      try await template.save()
                    } catch {
                      Log.persistence.error("Saving the checklist template on background failed: \(error)")
                    }
                  }
                )
              default:
                return .none
            }

          case let .openURL(url):
            guard let link = DeepLink(url: url) else {
              return .none
            }
            switch link {
              case let .stock(symbol):
                state.selectedTab = .watchlist
                // An unknown symbol leaves the current screen and stack alone: clear them only once there is something to push.
                guard state.watchlist.items[id: symbol] != nil else {
                  return .none
                }
                state.watchlist.destination = nil
                state.watchlist.path.removeAll()
                state.watchlist.showDetails(symbol: symbol)
            }
            return .none

          case .watchlist(.delegate(.refreshRequested)):
            return sync(after: nil)

          case let .syncFinished(report):
            // SyncEngine writes merged rows straight into @Shared, which onChange can't see (overview §12.3).
            return report.pulled > 0 ? publishSnapshot(state.watchlist.snapshotInputs) : .none

          case let .syncFailed(message):
            Log.sync.error("Watchlist sync failed: \(message)")
            return .none

          case .binding, .watchlist, .settings:
            return .none
        }
      }
    }
    // Attached outside `CombineReducers`: `onChange` only sees mutations made by the reducer it wraps (overview §12.3).
    .onChange(of: \.watchlist.snapshotInputs) { _, state in
      publishSnapshot(state.watchlist.snapshotInputs)
    }
    // Any edit of the watchlist (made by a child reducer) starts the 2 s sync debounce. Remote rows written by `SyncEngine`
    // happen outside any action, so they can't trigger a sync loop.
    .onChange(of: \.watchlist.items) { _, _ in
      sync(after: .seconds(2))
    }
  }

  // MARK: Internal

  @Dependency(\.connectivity) var connectivity
  @Dependency(\.continuousClock) var clock
  @Dependency(\.date) var date
  @Dependency(\.snapshotClient) var snapshotClient
  @Dependency(\.syncClient) var syncClient

  // MARK: Private

  /// The only `snapshotClient.publish` call site: debounced 1 s by default and cancellable by `CancelID.publishSnapshot`.
  /// With `debounced: false` it publishes at once and cancels any pending debounced publish.
  private func publishSnapshot(_ inputs: WatchlistFeature.SnapshotInputs, debounced: Bool = true) -> Effect<Action> {
    .run { [clock, date, snapshotClient, connectivity] _ in
      if debounced {
        try await clock.sleep(for: .seconds(1))
      }
      await snapshotClient.alsoSending(to: connectivity).publish(WatchlistSnapshot.make(items: inputs.items, quotes: inputs.quotes, now: date.now))
    }
    .cancellable(id: CancelID.publishSnapshot, cancelInFlight: true)
  }

  /// One sync, optionally debounced. Every trigger shares `CancelID.sync`, so a newer trigger replaces a pending one.
  /// The engine itself is single-flight, so cancelling a caller never cancels a run that is already in progress.
  private func sync(after delay: Duration?) -> Effect<Action> {
    .run { [clock, syncClient] send in
      if let delay {
        try await clock.sleep(for: delay)
      }
      do {
        await send(.syncFinished(try await syncClient.sync()))
      } catch {
        await send(.syncFailed(error.localizedDescription))
      }
    }
    .cancellable(id: CancelID.sync, cancelInFlight: true)
  }
}
