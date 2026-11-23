// Created by kai_chen on 5/4/21.

import Color
import Logging
import SettingsTab
import SwiftUI

// MARK: - WaitApp

@main
struct WaitApp: App {
  // MARK: Lifecycle

  init() {
    Logger.setupLogger()
  }

  // MARK: Internal

  var body: some Scene {
    WindowGroup {
      TabView {
        MainView()
          .tabItem {
            Image(systemName: "house")
          }

        SettingsView()
          .tabItem {
            Image(systemName: "gearshape")
          }
      }
      .accentColor(.mint)
    }
  }
}
