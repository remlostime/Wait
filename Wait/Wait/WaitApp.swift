// Created by kai_chen on 5/4/21.

import Color
// import Firebase
import PartialSheet
import Shake
import SwiftUI
import SwiftyBeaver
import Logging
//import Trace

//let logger = SwiftyBeaver.self

// MARK: - WaitApp

@main
struct WaitApp: App {
  // MARK: Lifecycle

  init() {
    setupShake()
    setupLogger()
//    setupFirebase()
  }

  // MARK: Internal

  var body: some Scene {
    WindowGroup {
      let sheetManager = PartialSheetManager()
      ContentView(stocks: [])
        .accentColor(.mint)
        .environmentObject(sheetManager)
    }
  }

  // MARK: Private

//  private let trace = Trace.shared

//  private func setupFirebase() {
//    FirebaseApp.configure()
//  }

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
