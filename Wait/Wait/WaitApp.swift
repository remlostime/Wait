// Created by kai_chen on 5/4/21.

import Color
import Logging
import SettingsTab
import Shake
import SwiftUI

// MARK: - WaitApp

@main
struct WaitApp: App {
  // MARK: Lifecycle

  init() {
    setupShake()
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

  // MARK: Private

  private func setupShake() {
    Shake.configuration.isInvokedByShakeDeviceEvent = true
    Shake.configuration.isInvokedByScreenshot = true
    Shake.configuration.isCrashReportingEnabled = true
    Shake.start(
      clientId: "EMFDruyQ3NpZJixuCtgi2LiTl83hjfngf3tRFL3F",
      clientSecret: "wh1riTvDR93wmB0itrbltVmOKMsFToZyM4O6Y65pPtARpvdiLq4Xtd1"
    )
  }
}
