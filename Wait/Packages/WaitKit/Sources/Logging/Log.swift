//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import os

// MARK: - LogChannel

/// A unified-logging category. Messages are logged with `.public` privacy, because this is a personal app and logs never leave the device.
public struct LogChannel: Sendable {
  // MARK: Lifecycle

  public init(category: String) {
    self.category = category
    logger = os.Logger(subsystem: Log.subsystem, category: category)
  }

  // MARK: Public

  public let category: String

  public func debug(_ message: String) {
    logger.debug("\(message, privacy: .public)")
  }

  public func info(_ message: String) {
    logger.info("\(message, privacy: .public)")
  }

  public func error(_ message: String) {
    logger.error("\(message, privacy: .public)")
  }

  // MARK: Private

  private let logger: os.Logger
}

// MARK: - Log

public enum Log {
  public static let subsystem = "com.chenkai.wait"

  public static let app = LogChannel(category: "app")
  public static let network = LogChannel(category: "network")
  public static let persistence = LogChannel(category: "persistence")
  public static let ui = LogChannel(category: "ui")
  public static let sync = LogChannel(category: "sync")
  public static let push = LogChannel(category: "push")
  public static let connectivity = LogChannel(category: "connectivity")
}
