// Created by kai_chen on 5/4/21.

import DesignSystem
import SettingsTab
import SwiftUI

// MARK: - WaitApp

@main
struct WaitApp: App {
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
