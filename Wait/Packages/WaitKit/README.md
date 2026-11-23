# WaitKit

Local Swift package holding every Wait module except the three Xcode targets (app, widget, watch app), which live in `Wait/project.yml`.

## Rules

- **One library product and one target per module.** Declare every `import` as a target dependency, because SwiftPM won't find undeclared modules reliably.
- **New targets use Swift 6 language mode**, the package default. Legacy targets moved from the old framework targets in plan 01 set `swiftSettings: legacySettings` (Swift 5 mode). They are deleted at the plan 02 cutover.
- **Tests use Swift Testing.** TCA tests are `@MainActor` and use `TestStore`.
- The app resolves this package through the Xcode project. A standalone `Package.resolved` here is gitignored.

## Commands

```sh
# All tests
cd Wait/Packages/WaitKit && xcodebuild test -scheme WaitKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation
```

## Targets (after plan 01)

| Target | Mode | Depends on |
|---|---|---|
| DesignSystem | Swift 5 (legacy) | – |
| Logging | Swift 6 | os |
| Model | Swift 5 (legacy) | DesignSystem, Money |
| CacheService | Swift 5 (legacy) | Model, Logging |
| Networking | Swift 5 (legacy) | Model, Logging |
| StockCharts | Swift 5 (legacy) | CacheService, Networking, Model, DesignSystem, Logging, Money, Alamofire, SwiftyJSON |
| Checklist | Swift 5 (legacy) | CacheService, DesignSystem, Model, Logging, TCA |
| ChecklistEditFeature | Swift 5 (legacy) | Logging, Model, TCA |
| LegacyStockDetails | Swift 5 (legacy) | CacheService, Networking, Logging, Checklist, DesignSystem, Model, StockCharts, Money, TCA |
| SettingsTab | Swift 5 (legacy) | ChecklistEditFeature, Model, TCA |
| ChecklistTests, ChecklistEditFeatureTests | Swift 5 (legacy) | the module under test, Model, TCA |
