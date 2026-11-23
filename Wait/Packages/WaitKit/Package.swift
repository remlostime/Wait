// swift-tools-version: 6.1
//
// WaitKit holds every Wait module except the three Xcode targets (app, widget, watch app).
// Plan 01 moves the legacy framework targets in here unchanged (Swift 5 language mode);
// plan 02 replaces them with Swift 6 modules. See docs/superpowers/plans/.
//
import PackageDescription

/// Legacy modules moved from framework targets keep Swift 5 language mode until the plan 02 cutover.
let legacySettings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

extension Target.Dependency {
  static let alamofire = Self.product(name: "Alamofire", package: "Alamofire")
  static let money = Self.product(name: "Money", package: "Money")
  static let swiftyJSON = Self.product(name: "SwiftyJSON", package: "SwiftyJSON")
}

let package = Package(
  name: "WaitKit",
  defaultLocalization: "en",
  platforms: [.iOS(.v17), .watchOS(.v10)],
  products: [
    .library(name: "DesignSystem", targets: ["DesignSystem"]),
    .library(name: "Logging", targets: ["Logging"]),
    .library(name: "Model", targets: ["Model"]),
    .library(name: "CacheService", targets: ["CacheService"]),
    .library(name: "Networking", targets: ["Networking"]),
    .library(name: "StockCharts", targets: ["StockCharts"]),
  ],
  dependencies: [
    // Legacy only — removed at the plan 02 cutover.
    .package(url: "https://github.com/Flight-School/Money", exact: "1.3.0"),
    .package(url: "https://github.com/Alamofire/Alamofire", exact: "5.5.0"),
    .package(url: "https://github.com/SwiftyJSON/SwiftyJSON", exact: "5.0.1"),
  ],
  targets: [
    .target(name: "DesignSystem", swiftSettings: legacySettings),
    .target(name: "Logging"),
    .target(name: "Model", dependencies: ["DesignSystem", .money], swiftSettings: legacySettings),
    .target(name: "CacheService", dependencies: ["Model", "Logging"], swiftSettings: legacySettings),
    .target(name: "Networking", dependencies: ["Model", "Logging"], swiftSettings: legacySettings),
    .target(
      name: "StockCharts",
      dependencies: ["CacheService", "Networking", "Model", "DesignSystem", "Logging", .money, .alamofire, .swiftyJSON],
      swiftSettings: legacySettings
    ),
  ],
  swiftLanguageModes: [.v6]
)
