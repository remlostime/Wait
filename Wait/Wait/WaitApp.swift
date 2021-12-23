// Created by kai_chen on 5/4/21.

import Color
import Logging
import PartialSheet
import Shake
import SwiftUI
import SwiftyBeaver

// MARK: - WaitApp

@main
struct WaitApp: App {
  // MARK: Lifecycle

  init() {
    setupShake()
    setupLogger()
  }

  // MARK: Internal

  var body: some Scene {
    WindowGroup {
      TabView {
        let sheetManager = PartialSheetManager()
        ContentView()
          .tabItem {
            Image(systemName: "house")
          }
          .environmentObject(sheetManager)

        SettingsView()
          .tabItem {
            Image(systemName: "gearshape")
          }
      }
      .accentColor(.waitMint)
//      .preferredColorScheme(.light	)
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

  private func setupLogger() {
    let console = ConsoleDestination()
    let file = FileDestination()
    let cloud = SBPlatformDestination(appID: "o8QNxr", appSecret: "vrhdvzltfSrrHDfjjzwdjkuboghtghnr", encryptionKey: "Y3ac3wvyk2piCsldmnzowqkxet26kPpJ")
    logger.addDestination(console)
    logger.addDestination(file)
    logger.addDestination(cloud)
  }
}
