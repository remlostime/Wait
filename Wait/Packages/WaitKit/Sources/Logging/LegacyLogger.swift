//
// Created by: kai_chen on 8/22/21.
// Copyright © 2021 Wait. All rights reserved.
//

import os

// MARK: - Logger

/// Legacy facade that keeps the existing `Logger.shared.verbose(...)` / `Logger.shared.error(...)` call sites
/// compiling after SwiftyBeaver's removal. Messages go to unified logging (subsystem `com.chenkai.wait`,
/// category `legacy`). Plan 02 deletes this file in favor of `Log` categories.
///
/// Inside this module `Logger` names this enum, so Apple's type is always written `os.Logger`.
public enum Logger {
  public static let shared = LegacyLogger()
}

// MARK: - LegacyLogger

public struct LegacyLogger: Sendable {
  // MARK: Public

  public func verbose(_ message: @autoclosure () -> Any, file: StaticString = #fileID, line: UInt = #line) {
    let text = Self.render(message(), file: file, line: line)
    logger.debug("\(text, privacy: .public)")
  }

  public func error(_ message: @autoclosure () -> Any, file: StaticString = #fileID, line: UInt = #line) {
    let text = Self.render(message(), file: file, line: line)
    logger.error("\(text, privacy: .public)")
  }

  // MARK: Internal

  static func render(_ message: Any, file: StaticString, line: UInt) -> String {
    "[\(file):\(line)] \(message)"
  }

  // MARK: Private

  private let logger = os.Logger(subsystem: "com.chenkai.wait", category: "legacy")
}
