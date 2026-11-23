// swift-tools-version: 6.1
import PackageDescription

extension Target.Dependency {
  static let tca = Self.product(name: "ComposableArchitecture", package: "swift-composable-architecture")
  static let dependencies = Self.product(name: "Dependencies", package: "swift-dependencies")
  static let dependenciesMacros = Self.product(name: "DependenciesMacros", package: "swift-dependencies")
  static let dependenciesTestSupport = Self.product(name: "DependenciesTestSupport", package: "swift-dependencies")
  static let sharing = Self.product(name: "Sharing", package: "swift-sharing")
  static let identifiedCollections = Self.product(name: "IdentifiedCollections", package: "swift-identified-collections")
}

let package = Package(
  name: "WaitKit",
  defaultLocalization: "en",
  platforms: [.iOS(.v17), .watchOS(.v10)],
  products: [
    .library(name: "AppFeature", targets: ["AppFeature"]),
    .library(name: "ChecklistFeature", targets: ["ChecklistFeature"]),
    .library(name: "DesignSystem", targets: ["DesignSystem"]),
    .library(name: "Domain", targets: ["Domain"]),
    .library(name: "Logging", targets: ["Logging"]),
    .library(name: "MarketDataClient", targets: ["MarketDataClient"]),
    .library(name: "Persistence", targets: ["Persistence"]),
    .library(name: "Connectivity", targets: ["Connectivity"]),
    .library(name: "SettingsFeature", targets: ["SettingsFeature"]),
    .library(name: "StockChartFeature", targets: ["StockChartFeature"]),
    .library(name: "StockDetailsFeature", targets: ["StockDetailsFeature"]),
    .library(name: "WatchlistFeature", targets: ["WatchlistFeature"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.26.2", traits: ["ComposableArchitecture2Deprecations"]),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.17.0"),
    .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.10.0"),
    .package(url: "https://github.com/pointfreeco/swift-identified-collections", from: "1.1.0"),
  ],
  targets: [
    // Core (Domain, Logging, DesignSystem and Persistence also build for watchOS)
    .target(name: "Domain"),
    .target(name: "Logging"),
    .target(name: "DesignSystem", dependencies: ["Domain"]),
    .target(name: "Persistence", dependencies: ["Domain", "Logging", .sharing, .identifiedCollections, .dependencies, .dependenciesMacros]),
    .target(name: "Connectivity", dependencies: ["Domain", .dependencies, .dependenciesMacros]),
    .target(name: "MarketDataClient", dependencies: ["Domain", "Logging", .dependencies, .dependenciesMacros]),

    // Features
    .target(name: "ChecklistFeature", dependencies: ["Domain", "Persistence", "DesignSystem", .tca]),
    .target(name: "StockChartFeature", dependencies: ["Domain", "MarketDataClient", "DesignSystem", .tca]),
    .target(name: "StockDetailsFeature", dependencies: ["Domain", "Persistence", "MarketDataClient", "StockChartFeature", "DesignSystem", .tca]),
    .target(name: "WatchlistFeature", dependencies: ["Domain", "Persistence", "MarketDataClient", "StockDetailsFeature", "ChecklistFeature", "DesignSystem", .tca]),
    .target(name: "SettingsFeature", dependencies: ["ChecklistFeature", "DesignSystem", .tca]),
    .target(name: "AppFeature", dependencies: ["Domain", "DesignSystem", "Logging", "Persistence", "SettingsFeature", "WatchlistFeature", .tca]),

    // Tests
    .testTarget(name: "DomainTests", dependencies: ["Domain"], resources: [.copy("Fixtures")]),
    .testTarget(name: "LoggingTests", dependencies: ["Logging"]),
    .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem", "Domain"]),
    .testTarget(name: "PersistenceTests", dependencies: ["Persistence", "Domain", .sharing, .identifiedCollections, .dependenciesTestSupport]),
    .testTarget(name: "ConnectivityTests", dependencies: ["Connectivity", "Domain"]),
    .testTarget(name: "MarketDataClientTests", dependencies: ["MarketDataClient", "Domain", .dependencies, .dependenciesTestSupport], resources: [.copy("Fixtures")]),
    .testTarget(name: "ChecklistFeatureTests", dependencies: ["ChecklistFeature", "Domain", "Persistence", .tca, .dependenciesTestSupport]),
    .testTarget(name: "StockChartFeatureTests", dependencies: ["StockChartFeature", "Domain", "MarketDataClient", .tca]),
    .testTarget(name: "StockDetailsFeatureTests", dependencies: ["StockDetailsFeature", "Domain", "MarketDataClient", .tca]),
    .testTarget(
      name: "WatchlistFeatureTests",
      dependencies: ["WatchlistFeature", "ChecklistFeature", "Domain", "MarketDataClient", "Persistence", "StockDetailsFeature", .tca, .dependenciesTestSupport]
    ),
    .testTarget(name: "SettingsFeatureTests", dependencies: ["SettingsFeature", "ChecklistFeature", .tca, .dependenciesTestSupport]),
    .testTarget(
      name: "AppFeatureTests",
      dependencies: ["AppFeature", "Domain", "MarketDataClient", "Persistence", "StockDetailsFeature", "WatchlistFeature", .tca, .dependenciesTestSupport]
    ),
  ],
  swiftLanguageModes: [.v6]
)
