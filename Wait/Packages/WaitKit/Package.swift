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
  static let tca = Self.product(name: "ComposableArchitecture", package: "swift-composable-architecture")
}

let package = Package(
  name: "WaitKit",
  defaultLocalization: "en",
  platforms: [.iOS(.v17), .watchOS(.v10)],
  products: [
    .library(name: "Domain", targets: ["Domain"]),
    .library(name: "DesignSystem", targets: ["DesignSystem"]),
    .library(name: "Logging", targets: ["Logging"]),
    .library(name: "Model", targets: ["Model"]),
    .library(name: "CacheService", targets: ["CacheService"]),
    .library(name: "Networking", targets: ["Networking"]),
    .library(name: "StockCharts", targets: ["StockCharts"]),
    .library(name: "Checklist", targets: ["Checklist"]),
    .library(name: "ChecklistEditFeature", targets: ["ChecklistEditFeature"]),
    .library(name: "LegacyStockDetails", targets: ["LegacyStockDetails"]),
    .library(name: "SettingsTab", targets: ["SettingsTab"]),
    .library(name: "Persistence", targets: ["Persistence"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/pointfreeco/swift-composable-architecture",
      from: "1.26.2",
      traits: ["ComposableArchitecture2Deprecations"]
    ),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.17.0"),
    .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.10.0"),
    .package(url: "https://github.com/pointfreeco/swift-identified-collections", from: "1.1.0"),
    // Legacy only — removed at the plan 02 cutover.
    .package(url: "https://github.com/Flight-School/Money", exact: "1.3.0"),
    .package(url: "https://github.com/Alamofire/Alamofire", exact: "5.5.0"),
    .package(url: "https://github.com/SwiftyJSON/SwiftyJSON", exact: "5.0.1"),
  ],
  targets: [
    .target(name: "Domain"),
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
    .target(
      name: "Checklist",
      dependencies: ["CacheService", "DesignSystem", "Model", "Logging", .tca],
      swiftSettings: legacySettings
    ),
    .target(name: "ChecklistEditFeature", dependencies: ["Logging", "Model", .tca], swiftSettings: legacySettings),
    .target(
      name: "LegacyStockDetails",
      dependencies: ["CacheService", "Networking", "Logging", "Checklist", "DesignSystem", "Model", "StockCharts", .money, .tca],
      swiftSettings: legacySettings
    ),
    .target(name: "SettingsTab", dependencies: ["ChecklistEditFeature", "Model", .tca], swiftSettings: legacySettings),
    .target(
      name: "Persistence",
      dependencies: [
        "Domain",
        "Logging",
        .product(name: "Sharing", package: "swift-sharing"),
        .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesMacros", package: "swift-dependencies"),
      ]
    ),
    .testTarget(name: "DomainTests", dependencies: ["Domain"], resources: [.copy("Fixtures")]),
    .testTarget(name: "LoggingTests", dependencies: ["Logging"]),
    .testTarget(
      name: "PersistenceTests",
      dependencies: [
        "Persistence",
        "Domain",
        .product(name: "Sharing", package: "swift-sharing"),
        .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ]
    ),
    .testTarget(name: "ChecklistTests", dependencies: ["Checklist", "Model", .tca], swiftSettings: legacySettings),
    .testTarget(name: "ChecklistEditFeatureTests", dependencies: ["ChecklistEditFeature", "Model", .tca], swiftSettings: legacySettings),
  ],
  swiftLanguageModes: [.v6]
)
