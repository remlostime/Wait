//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Domain
import Foundation
import Persistence
import SettingsFeature
import SwiftUI
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
  }

  public enum CancelID: Hashable, Sendable {
    case publishSnapshot
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
            return publishSnapshot(state.watchlist.snapshotInputs)

          case let .scenePhaseChanged(phase):
            switch phase {
              case .active:
                return .send(.watchlist(.sceneBecameActive))
              case .background:
                // `@Shared(.fileStorage)` throttles writes, so flush them before the app is suspended (overview risk 5).
                @Shared(.checklistTemplate) var template
                return .run { [items = state.watchlist.$items, template = $template] _ in
                  try await items.save()
                  try await template.save()
                }
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
                state.watchlist.destination = nil
                state.watchlist.path.removeAll()
                state.watchlist.showDetails(symbol: symbol)
            }
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
  }

  // MARK: Internal

  @Dependency(\.continuousClock) var clock
  @Dependency(\.date) var date
  @Dependency(\.snapshotClient) var snapshotClient

  // MARK: Private

  /// The only `snapshotClient.publish` call site: debounced 1 s and cancellable by `CancelID.publishSnapshot`.
  private func publishSnapshot(_ inputs: WatchlistFeature.SnapshotInputs) -> Effect<Action> {
    .run { [clock, date, snapshotClient] _ in
      try await clock.sleep(for: .seconds(1))
      await snapshotClient.publish(WatchlistSnapshot.make(items: inputs.items, quotes: inputs.quotes, now: date.now))
    }
    .cancellable(id: CancelID.publishSnapshot, cancelInFlight: true)
  }
}
