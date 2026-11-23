//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

#if os(iOS)
  import ComposableArchitecture
  import Foundation
  import Logging
  import Persistence
  import UIKit

  // MARK: - AppDelegate

  /// Owns the root store. `@UIApplicationDelegateAdaptor` creates it before the `App` body runs, so the legacy migration runs inside the lazy
  /// store initializer, before any `@Shared(.watchlist)` is read (overview risk 26).
  @MainActor
  public final class AppDelegate: NSObject, UIApplicationDelegate {
    public lazy var store: StoreOf<AppFeature> = {
      do {
        let report = try LegacyMigration.live.runIfNeeded(now: Date())
        if report.didRun {
          Log.persistence.info("Legacy migration: \(report.migratedItems) items, template migrated: \(report.migratedTemplate)")
        }
      } catch {
        Log.persistence.error("Legacy migration failed (will retry next launch): \(error)")
      }
      return Store(initialState: AppFeature.State()) {
        AppFeature()
      }
    }()

    public func application(
      _ application: UIApplication,
      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
      store.send(.appDelegate(.didFinishLaunching))
      return true
    }
  }
#endif
