//
// Created by: kai_chen on 8/22/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import SwiftyBeaver

public enum Logger {
  public static let shared = SwiftyBeaver.self

  public static func setupLogger() {
    shared.addDestination(ConsoleDestination())
    shared.addDestination(FileDestination())
  }
}
