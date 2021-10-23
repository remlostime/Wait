// Created by kai_chen on 5/4/21.

import Color
import Logging
import Firebase
import PartialSheet
import Shake
import SwiftUI
import SwiftyBeaver
// import Trace

// let logger = SwiftyBeaver.self

// MARK: - WaitApp

@main
struct WaitApp: App {
  // MARK: Lifecycle

  init() {
    setupShake()
    setupLogger()
    setupFirebase()
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
      .accentColor(Color.mint)
    }
  }

  // MARK: Private

//  private let trace = Trace.shared

  private func setupFirebase() {
    FirebaseApp.configure()
    Database.database().isPersistenceEnabled = true
  }

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
