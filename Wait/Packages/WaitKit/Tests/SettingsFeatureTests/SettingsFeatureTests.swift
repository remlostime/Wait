//
// Created by: Claude on 2026-11-23.
// Copyright © 2021 Wait. All rights reserved.
//

import ChecklistFeature
import ComposableArchitecture
import DependenciesTestSupport
import SettingsFeature
import Testing

@MainActor
@Suite(.dependencies { $0.defaultFileStorage = .inMemory })
struct SettingsFeatureTests {
  @Test func templateRowPushesTheEditor() async {
    let store = TestStore(initialState: SettingsFeature.State(appVersion: "2.0 (1)")) { SettingsFeature() }
    await store.send(.checklistTemplateTapped) {
      $0.path.append(.checklistTemplate(ChecklistTemplateFeature.State()))
    }
  }

  @Test func appVersionFormatting() {
    #expect(SettingsFeature.State.versionString(info: ["CFBundleShortVersionString": "2.0", "CFBundleVersion": "7"]) == "2.0 (7)")
    #expect(SettingsFeature.State.versionString(info: nil) == "? (?)")
  }
}
