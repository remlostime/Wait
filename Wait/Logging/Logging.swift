//
// Created by: kai_chen on 8/22/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import SwiftyBeaver

public struct Logger {
  public static let shared = SwiftyBeaver.self

  public static func setupLogger() {
    let console = ConsoleDestination()
    let file = FileDestination()
    let cloud = SBPlatformDestination(
      appID: "o8QNxr",
      appSecret: "vrhdvzltfSrrHDfjjzwdjkuboghtghnr",
      encryptionKey: "Y3ac3wvyk2piCsldmnzowqkxet26kPpJ")
    shared.addDestination(console)
    shared.addDestination(file)
    shared.addDestination(cloud)
  }
}
