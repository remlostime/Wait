//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

// MARK: - CallRecorder

actor CallRecorder {
  private(set) var values: [String] = []

  func record(_ value: String) {
    values.append(value)
  }
}
