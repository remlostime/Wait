//
// Created by: kai_chen on 5/4/21.
// Copyright © 2021 Wait. All rights reserved.
//

import AppFeature
import SwiftUI

// MARK: - WaitApp

@main
struct WaitApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup {
      AppView(store: appDelegate.store)
    }
  }
}
