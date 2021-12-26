// Created by kai_chen on 5/4/21.

import Color
import Logging
import PartialSheet
import SettingsTab
import Shake
import SwiftUI
import WaitlistTab

// MARK: - WaitApp

@main
struct WaitApp: App {
  // MARK: Lifecycle

  init() {
    setupShake()
    Logger.setupLogger()
  }

  // MARK: Internal
  //let sheetManager = PartialSheetManager()

  var body: some Scene {
    WindowGroup {
      TabView {
        MainView()
          .tabItem {
            Image(systemName: "house")
          }
//          .environmentObject(self.sheetManager)

        SettingsView()
          .tabItem {
            Image(systemName: "gearshape")
          }
      }
      .accentColor(.waitMint)
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
