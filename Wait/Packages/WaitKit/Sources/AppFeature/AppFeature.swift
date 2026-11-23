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
    public var push = PushFeature.State()
  }

  public enum Action: BindableAction {
    case binding(BindingAction<State>)
    case scenePhaseChanged(ScenePhase)
    case openURL(URL)
    case appDelegate(AppDelegateAction)
    case watchlist(WatchlistFeature.Action)
    case settings(SettingsFeature.Action)
    case push(PushFeature.Action)
    case syncDebounceElapsed
    case syncFinished(SyncReport)
    case syncFailed(String)
  }

  public enum CancelID: Hashable, Sendable {
    case publishSnapshot
    /// The pending debounce of the edit-triggered sync. A newer trigger replaces it.
    case syncDebounce
    /// A sync that is running. Never cancelled by a newer trigger: the engine is single-flight and a second `syncClient.sync()`
    /// joins the run, so cancelling this effect would only drop the `.syncFinished` result.
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
      Scope(\.push, action: \.push) {
        PushFeature()
      }
      Reduce { state, action in
        switch action {
          case .appDelegate(.didFinishLaunching):
            // Publish once on launch, so the widget has data even before any quote changes.
            return .merge(
              publishSnapshot(state.watchlist.snapshotInputs),
              .run { [connectivity] _ in await connectivity.activate() },
              .send(.push(.launched))
            )

          // The push callbacks go to `PushFeature` as actions; `Reducer.reduce` and `Effect.map` are deprecated in TCA 1.25+.
          case let .appDelegate(.didRegisterForRemoteNotifications(deviceToken)):
            return .send(.push(.registered(deviceToken)))

          case let .appDelegate(.didFailToRegisterForRemoteNotifications(message)):
            return .send(.push(.registrationFailed(message)))

          case let .push(.delegate(.openStock(symbol))):
            guard let url = URL(string: "wait://stock/\(symbol)") else {
              return .none
            }
            return .send(.openURL(url))

          case let .scenePhaseChanged(phase):
            switch phase {
              case .active:
                return .merge(.send(.watchlist(.sceneBecameActive)), .send(.settings(.sceneBecameActive)), sync(after: nil))
              case .background:
                // `@Shared(.fileStorage)` throttles writes, so flush them before the app is suspended (overview risk 5).
                // The snapshot is published at once, because the debounce might never fire in a suspended app. Starting it also cancels
                // the pending debounced publish (`cancelInFlight`).
                @Shared(.checklistTemplate) var template
                @Shared(.syncState) var syncState
                return .merge(
                  publishSnapshot(state.watchlist.snapshotInputs, debounced: false),
                  .run { [items = state.watchlist.$items, template = $template, syncState = $syncState] _ in
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
                    // The cursor and acknowledgements must outlive the throttle too, or a killed app re-pulls and re-pushes.
                    do {
                      try await syncState.save()
                    } catch {
                      Log.persistence.error("Saving the sync state on background failed: \(error)")
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

          case .syncDebounceElapsed:
            return runSync()

          case let .syncFinished(report):
            // SyncEngine writes merged rows straight into @Shared, which onChange can't see (overview §12.3).
            // Pulled rows also arrive without quotes, so the ones that are missing are loaded; the quotes then change
            // `snapshotInputs`, which republishes through `onChange`.
            return .merge(
              report.pulled > 0 ? publishSnapshot(state.watchlist.snapshotInputs) : .none,
              report.applied > 0 ? .send(.watchlist(.missingQuotesRequested)) : .none
            )

          case let .syncFailed(message):
            Log.sync.error("Watchlist sync failed: \(message)")
            return .none

          case .binding, .watchlist, .settings, .push:
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

  /// One sync, optionally debounced. A delayed trigger waits under `CancelID.syncDebounce`, where a newer trigger replaces it.
  /// The run itself goes under `CancelID.sync` and is never cancelled by a newer trigger, so `.syncFinished` always arrives.
  /// The engine is single-flight: a trigger that lands during a run joins it and asks it for one more pass.
  private func sync(after delay: Duration?) -> Effect<Action> {
    // An immediate sync already carries every edit made so far, so it replaces a pending debounce.
    guard let delay else {
      return .merge(.cancel(id: CancelID.syncDebounce), runSync())
    }
    return .run { [clock] send in
      try await clock.sleep(for: delay)
      await send(.syncDebounceElapsed)
    }
    .cancellable(id: CancelID.syncDebounce, cancelInFlight: true)
  }

  private func runSync() -> Effect<Action> {
    .run { [syncClient] send in
      do {
        await send(.syncFinished(try await syncClient.sync()))
      } catch {
        await send(.syncFailed(error.localizedDescription))
      }
    }
    .cancellable(id: CancelID.sync)
  }
}
