//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ChecklistFeature
import ComposableArchitecture
import Foundation

// MARK: - SettingsFeature

/// Plan 02 scope: the checklist template editor and the app version. Plans 04/05/06 add account, sync and alerts sections (overview §12.3).
@Reducer
public struct SettingsFeature {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  @Reducer
  public enum Path {
    case checklistTemplate(ChecklistTemplateFeature)
  }

  @ObservableState
  public struct State: Equatable {
    // MARK: Lifecycle

    public init(appVersion: String = State.versionString(info: Bundle.main.infoDictionary)) {
      self.appVersion = appVersion
    }

    // MARK: Public

    public var path = StackState<Path.State>()
    public var appVersion: String

    public static func versionString(info: [String: Any]?) -> String {
      let version = info?["CFBundleShortVersionString"] as? String ?? "?"
      let build = info?["CFBundleVersion"] as? String ?? "?"
      return "\(version) (\(build))"
    }
  }

  public enum Action {
    case checklistTemplateTapped
    case path(StackActionOf<Path>)
  }

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
        case .checklistTemplateTapped:
          state.path.append(.checklistTemplate(ChecklistTemplateFeature.State()))
          return .none

        case .path:
          return .none
      }
    }
    .forEach(\.path, action: \.path)
  }
}

// MARK: - SettingsFeature.Path.State + Equatable

extension SettingsFeature.Path.State: Equatable {}
