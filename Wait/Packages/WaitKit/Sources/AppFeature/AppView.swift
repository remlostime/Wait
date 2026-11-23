//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import DesignSystem
import SettingsFeature
import SwiftUI
import WatchlistFeature

// MARK: - AppView

public struct AppView: View {
  // MARK: Lifecycle

  public init(store: StoreOf<AppFeature>) {
    self.store = store
  }

  // MARK: Public

  public var body: some View {
    TabView(selection: $store.selectedTab) {
      WatchlistView(store: store.scope(\.watchlist, action: \.watchlist))
        .tabItem { Label("Watchlist", systemImage: "list.bullet.rectangle") }
        .tag(AppFeature.Tab.watchlist)
      SettingsView(store: store.scope(\.settings, action: \.settings))
        .tabItem { Label("Settings", systemImage: "gearshape") }
        .tag(AppFeature.Tab.settings)
    }
    .tint(Palette.accent)
    .onOpenURL { store.send(.openURL($0)) }
    .onChange(of: scenePhase) { _, phase in
      store.send(.scenePhaseChanged(phase))
    }
  }

  // MARK: Private

  @Bindable private var store: StoreOf<AppFeature>
  @Environment(\.scenePhase) private var scenePhase
}
