// swift-tools-version: 6.1
//
// WaitKit holds every Wait module except the three Xcode targets (app, widget, watch app).
// Plan 01 moves the legacy framework targets in here unchanged (Swift 5 language mode);
// plan 02 replaces them with Swift 6 modules. See docs/superpowers/plans/.
//
import PackageDescription

/// Legacy modules moved from framework targets keep Swift 5 language mode until the plan 02 cutover.
let legacySettings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
  name: "WaitKit",
  defaultLocalization: "en",
  platforms: [.iOS(.v17), .watchOS(.v10)],
  products: [
    .library(name: "DesignSystem", targets: ["DesignSystem"]),
  ],
  targets: [
    .target(name: "DesignSystem", swiftSettings: legacySettings),
  ],
  swiftLanguageModes: [.v6]
)
