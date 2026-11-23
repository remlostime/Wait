//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation

/// UIApplicationDelegate callbacks forwarded into the store. Plan 06 adds the remote-notification registration cases.
public enum AppDelegateAction: Equatable, Sendable {
  case didFinishLaunching
}
