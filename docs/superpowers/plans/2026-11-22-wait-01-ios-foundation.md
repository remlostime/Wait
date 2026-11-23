# Wait 01 — iOS Foundation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Deviations from overview** (three):
> - The overview's plan 01 definition of done uses `git grep -n "apikey=\|clientId:\|clientSecret:"`. That grep also matches the plan docs and `scripts/check-secrets.sh`, which quote those patterns, so this plan runs it with `-- . ':!docs' ':!scripts/check-secrets.sh'`.
> - The work is split into five chunks so each stays under 1,000 lines: Chunk 1 (Tasks 1–4), Chunk 2 (Task 5), Chunk 3 (Tasks 6–10), Chunk 4 (Tasks 11–12) and Chunk 5 (Tasks 13–14). The tasks and their order are unchanged.
> - The watch XcodeGen target is named `WaitWatch` from Task 2 on (overview §3.1). Its sources stay in `Wait/WaitWatch Watch App/` until plan 03 renames the folder, and the embedded product is `WaitWatch.app`.

**Goal:** Keep the app behaving exactly as it does today while moving it onto new foundations:
- an XcodeGen-generated project with only three targets (app, widget, watch)
- iOS 17 / watchOS 10
- every framework module inside the local Swift package `WaitKit`
- TCA 1.26
- no credentials in source
- no Shake or SwiftyBeaver

**Architecture:** `Wait/project.yml` becomes the only source of truth for the Xcode project. The work runs in this order:
1. Reach parity with the hand-made project.
2. Raise the platform floor, fix the watch target and strip secrets.
3. Move the framework targets into `Wait/Packages/WaitKit` one at a time, leaf modules first. Use `git mv` so history follows, and keep the app building after every commit.

Legacy modules keep their names, except `StockDetailsFeature`, which becomes `LegacyStockDetails`. They compile in Swift 5 language mode, and plan 02 replaces them. TCA is upgraded last, once it is linked into a single binary.

**Tech Stack:**
- Xcode 27.0 / Swift 6.4, XcodeGen 2.46, SwiftPM tools 6.1
- TCA 1.26.2 with trait `ComposableArchitecture2Deprecations`
- Swift Testing
- `os.Logger`
- Legacy dependencies pinned exactly: Money 1.3.0, Alamofire 5.5.0, SwiftyJSON 5.0.1

---

## Prerequisites

1. **Read the overview first:** `docs/superpowers/plans/2026-11-22-wait-00-overview.md`, especially §2 (decisions), §3.1 (target graph), §5 (commands and conventions), §11 (risks) and §12 (file layout).
2. **(manual: user) Commit the planning docs so a worktree can see them.** When this plan was written, `CLAUDE.md` (staged), `AGENTS.md` (an untracked symlink) and `docs/` (untracked) were not committed on `ck/new-version`, and a new worktree would not contain them. From `/Users/ckai/code/Wait`:
   ```sh
   git add CLAUDE.md AGENTS.md docs && git commit -m "docs: add CLAUDE.md and modernization plans"
   ```
3. **Worktree:** use superpowers:using-git-worktrees to create a worktree off `ck/new-version`, never `master`, for example:
   ```sh
   git -C /Users/ckai/code/Wait worktree add ../Wait-plan01 -b ck/plan-01-foundation ck/new-version
   ```
   Every command in this plan uses the absolute path `/Users/ckai/code/Wait`. **If you run in a worktree, replace that prefix with the worktree root in every command.** Shell state doesn't persist between tool calls, so each command block is self-contained.
4. **Tools.** Expected output is shown under each command.
   ```sh
   xcodebuild -version | head -1
   xcodegen --version
   xcrun simctl list devices available | grep -E "iPhone 17 \(|Apple Watch Series 12 \(42mm\)"
   ```
   ```
   Xcode 27.0
   Version: 2.46.0
   ```
   The simctl lines must include an `iPhone 17 (…)` under `-- iOS 27.0 --` and an `Apple Watch Series 12 (42mm) (…)` under `-- watchOS 27.0 --`. SwiftFormat is optional (`brew install swiftformat`), and no step requires it.
5. **Sandbox note.** SwiftPM compiles package manifests inside `sandbox-exec`. Inside an already-sandboxed agent shell, package resolution fails with `sandbox-exec: sandbox_apply: Operation not permitted`. Run every `xcodebuild` and `xcodegen` command **outside the agent sandbox** (in Claude Code, set `dangerouslyDisableSandbox: true` for those Bash calls). Don't change project settings to work around it.
6. **Keys.** (manual: user) Task 5 needs a **new** Twelve Data API key. Builds and tests don't need a real key; without one the app still launches, but quotes don't load.
7. **Skills:**
   - superpowers:test-driven-development for Tasks 5 and 13, which add the secret-scan check and the reducer tests. Task 11 runs the moved tests. The other tasks are structural and are verified by build and test runs.
   - swiftui-expert:swiftui-expert-skill for the view ports in Task 13.
   - ios-code-best-practice:ios-code-best-practice only for its Swift concurrency and module-dependency guidance. The Pinterest-specific parts don't apply.
8. The user's global CLAUDE.md says "don't build unless asked". Running this plan is that request, so every build and test step below is required.
9. **Never hand-edit `Wait/Wait.xcodeproj/project.pbxproj` after Task 2.** Edit `Wait/project.yml`, then run `xcodegen generate`.

### Build and test commands used in this plan

Every task repeats the command it needs in full. They are listed here for reference.

```sh
# A. Regenerate the Xcode project
cd /Users/ckai/code/Wait/Wait && xcodegen generate

# B. Build the app (from Task 4 on this also builds the embedded watch app)
xcodebuild -project /Users/ckai/code/Wait/Wait/Wait.xcodeproj -scheme Wait \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -skipMacroValidation -skipPackagePluginValidation build 2>&1 | tail -3

# C. App-scheme tests (Tasks 2–11 only; later tests live in the package)
xcodebuild test -project /Users/ckai/code/Wait/Wait/Wait.xcodeproj -scheme Wait \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -skipMacroValidation -skipPackagePluginValidation 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)" | tail -3

# D. Package tests (Task 11 on)
cd /Users/ckai/code/Wait/Wait/Packages/WaitKit && xcodebuild test -scheme WaitKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -skipMacroValidation -skipPackagePluginValidation 2>&1 | grep -E "Executed|Test run|TEST (SUCCEEDED|FAILED)" | tail -4

# E. Watch build (Task 4 on)
xcodebuild -project /Users/ckai/code/Wait/Wait/Wait.xcodeproj -scheme WaitWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 12 (42mm),OS=27.0' \
  -skipMacroValidation -skipPackagePluginValidation build 2>&1 | tail -3
```

---

## File Structure

**Created**
| Path | Responsibility |
|---|---|
| `docs/superpowers/plans/2026-11-22-wait-01-baseline-log.md` | Records what built and passed under Xcode 27 before any change, and which verification mode applies |
| `Wait/project.yml` | XcodeGen spec; the only source of truth for `Wait.xcodeproj` |
| `Wait/Config/Base.xcconfig` | Project-wide build settings; includes the optional `Secrets.xcconfig` |
| `Wait/Config/Secrets.example.xcconfig` | Committed template listing the secret build settings |
| `Wait/Config/Secrets.xcconfig` | **Gitignored.** The real `TWELVE_DATA_API_KEY` |
| `Wait/WaitWatch Watch App/Info.plist` | Carries `TwelveDataAPIKey` for the watch; Xcode merges the generated `INFOPLIST_KEY_*` values into it |
| `scripts/check-secrets.sh` | Fails when a tracked file looks like it contains a hard-coded credential |
| `Wait/Packages/WaitKit/Package.swift` | Local package manifest: products, targets, pinned legacy dependencies |
| `Wait/Packages/WaitKit/README.md` | Package layout and rules |
| `Wait/Packages/WaitKit/Sources/Logging/LegacyLogger.swift` | `Logger.shared.verbose/error` facade backed by `os.Logger` (replaces SwiftyBeaver) |

**Moved into `Wait/Packages/WaitKit/Sources/`** (with `git mv`, so history follows)
| From | To |
|---|---|
| `Wait/Color/*.swift` + `Wait/Size/Size.swift` | `Sources/DesignSystem/` |
| `Wait/Logging/Logging.swift` | `Sources/Logging/LegacyLogger.swift` (rewritten) |
| `Wait/Model/*.swift` | `Sources/Model/` |
| `Wait/CacheService/*.swift` | `Sources/CacheService/` |
| `Wait/Networking/*.swift` | `Sources/Networking/` |
| `Wait/StockCharts/Stock/*.swift` | `Sources/StockCharts/` |
| `Wait/Checklist/*.swift` | `Sources/Checklist/` |
| `Wait/ChecklistEditFeature/*.swift` | `Sources/ChecklistEditFeature/` |
| `Wait/StockDetailsFeature/**` | `Sources/LegacyStockDetails/**` (module renamed) |
| `Wait/SettingsTab/SettingsView.swift` | `Sources/SettingsTab/` |
| `Wait/ChecklistTests/*`, `Wait/ChecklistEditFeatureTests/*` | `Tests/ChecklistTests/`, `Tests/ChecklistEditFeatureTests/` |

**Modified:** `.gitignore` (adds `Wait/Config/Secrets.xcconfig`, `Wait/Packages/WaitKit/.build/`, `Wait/Packages/WaitKit/.swiftpm/` and `Wait/Packages/WaitKit/Package.resolved`), `CLAUDE.md`, `Wait/Wait/Info.plist`, `Wait/WaitWidget/Info.plist`, `Wait/Wait/WaitApp.swift`, `Wait/WaitWatch Watch App/PriceHistoryNetworkClient.swift`, the `import` lines of every file that imported `Color`, `Size` or `StockDetailsFeature`, and the generated `Wait/Wait.xcodeproj`.

**Deleted:**
- the framework `Info.plist` and `*.h` files
- `Wait/Checklist/Checklist.docc`
- `Wait/UI/` (unused)
- `Wait/StockDetailsFeatureTests/` (vacuous test plus an orphan snapshot)
- `Wait/GoogleService-Info.plist` (unused Firebase config)
- `Wait/bitrise_configuration.plist` (APM token)
- the `Unused Code` aggregate target and the `Color` scheme

---

## Chunk 1: Toolchain and generated project

### Task 1: Record the Xcode 27 baseline

**Files:**
- Create: `docs/superpowers/plans/2026-11-22-wait-01-baseline-log.md`
- Modify: `CLAUDE.md` (the `-destination` lines of its three `xcodebuild` commands)

- [ ] **Step 1: Resolve packages with the untouched project** — NOT RUN (code-only)

```sh
xcodebuild -resolvePackageDependencies -project /Users/ckai/code/Wait/Wait/Wait.xcodeproj -scheme Wait 2>&1 | tail -20
```
Expected: a `Resolved source packages:` list that includes `swift-composable-architecture: … @ 0.31.0`, `Money: … @ 1.3.0`, `shake-ios: … @ 14.4.0`, `SwiftyBeaver: … @ 1.9.5`, `Alamofire: … @ 5.5.0` and `SwiftyJSON: … @ 5.0.1`. If you see `Invalid manifest`, copy the first error line into the log in Step 5.

- [ ] **Step 2: Build the app as it is today** — NOT RUN (code-only)

```sh
xcodebuild -project /Users/ckai/code/Wait/Wait/Wait.xcodeproj -scheme Wait \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -skipMacroValidation -skipPackagePluginValidation build > /tmp/wait-baseline-build.log 2>&1; \
  tail -3 /tmp/wait-baseline-build.log; grep -m 10 "error:" /tmp/wait-baseline-build.log
```
Expected, when it works: `** BUILD SUCCEEDED **` and no `error:` lines. If it fails, keep `/tmp/wait-baseline-build.log`, because Task 2 onward compares against it.

- [ ] **Step 3: Run the three real test targets** — NOT RUN (code-only)

The shared `Wait` scheme also references six deleted test targets, so run the real ones explicitly:
```sh
xcodebuild test -project /Users/ckai/code/Wait/Wait/Wait.xcodeproj -scheme Wait \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation \
  -only-testing:ChecklistTests -only-testing:ChecklistEditFeatureTests -only-testing:StockDetailsFeatureTests 2>&1 \
  | grep -E "Executed|TEST (SUCCEEDED|FAILED)" | tail -3
```
Expected: `Executed 5 tests, with 0 failures` and `** TEST SUCCEEDED **`.

- [ ] **Step 4: Build the watch target** — NOT RUN (code-only)

There is no shared watch scheme yet, so build the target directly:
```sh
cd /Users/ckai/code/Wait/Wait && xcodebuild -project Wait.xcodeproj -target "WaitWatch Watch App" -sdk watchsimulator \
  -skipMacroValidation -skipPackagePluginValidation build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`. Record a failure in the log rather than fixing it here.

- [x] **Step 5: Write the baseline log**

Create `docs/superpowers/plans/2026-11-22-wait-01-baseline-log.md`. Fill in every `<…>` from Steps 1–4.
```markdown
# Plan 01 baseline — Xcode 27

Recorded: <YYYY-MM-DD> on <hostname>, Xcode 27.0 (27A266a)

| Check | Result |
|---|---|
| Package resolution (Step 1) | <OK / FAILED: first error line> |
| App build, `Wait` scheme (Step 2) | <BUILD SUCCEEDED / FAILED: first 5 `error:` lines with file paths> |
| Tests, 3 targets (Step 3) | <Executed 5 tests, with 0 failures / FAILED: …> |
| Watch target build (Step 4) | <BUILD SUCCEEDED / FAILED: …> |

**Verification mode:** <strict / red-baseline>
**Failing third-party packages (red-baseline only):** <e.g. swift-composable-architecture 0.31.0, shake-ios 14.4.0>
**Parity data seeded on simulator:** <yes, UDID … / no>
```

- [x] **Step 6: Choose the verification mode for Tasks 2–13**

Use the first rule that matches and write the mode into the log.

1. **Strict mode.** Steps 2–4 all succeeded. From here on, every task keeps the app build, the watch build and every test green.
2. **Red-baseline mode.** The app build failed **only** because of third-party packages. One failing package also makes Wait targets fail through cascade errors, so the check looks at failing *targets*, not at file paths. Run both commands below:
   ```sh
   # (i) Every failing target, as reported by xcodebuild
   grep -oE "\(in target '[^']+' from project '[^']+'\)" /tmp/wait-baseline-build.log | sort -u | tee /tmp/wait-baseline-failing-targets.txt
   # (ii) Errors in Wait's own sources that are NOT cascade errors from a broken dependency
   grep -E "error:" /tmp/wait-baseline-build.log | grep -v "/SourcePackages/checkouts/" \
     | grep -vE "couldn't be opened|Clang dependency scanning failure|Unable to resolve module dependency|no such module '"
   ```
   Rule 2 applies when both of these hold:
   - Every line from (i) names either a **third-party project**, or a project `Wait` (from Task 6 on, also `WaitKit`) target that **depends, directly or transitively, on a failing third-party project**. Check the dependencies with `grep -n -A25 "^  <Target>:" /Users/ckai/code/Wait/Wait/project.yml`, or with `Package.swift` for WaitKit targets.
     - Third-party projects at baseline: `swift-composable-architecture` and its own dependencies (`swift-custom-dump`, `swift-case-paths`, `combine-schedulers`, `xctest-dynamic-overlay`, `swift-identified-collections`, `swift-collections`), plus `shake-ios`, `SwiftyBeaver`, `Money`, `Alamofire`, `SwiftyJSON` and `swift-snapshot-testing`.
     - Cascade lines name the broken module, but they aren't the cause: a `.swiftmodule` that `couldn't be opened`, a `Clang dependency scanning failure`, `Unable to resolve module dependency: 'ComposableArchitecture'`, or `no such module '<third-party module>'`.
   - (ii) prints nothing, or prints only `no such module` / `Unable to resolve` lines that name a failing package's module.

   In this mode, a task in Tasks 2–12 counts as verified when all of these hold:
   - (a) `xcodegen generate` succeeds.
   - (b) The new build log passes the same two checks. Save it to a file, for example by adding `> /tmp/wait-build.log 2>&1` to command B, then run (i) and (ii) on it. Every failing target must still trace back to a failing third-party project. A failing project or target that isn't explained that way is a real regression: fix it before you commit.
   - (c) From Task 6 on, the package scheme (`WaitKit` in Task 6, while the package has one product; `WaitKit-Package` from Task 7) builds and tests green for every target that doesn't depend on a failing package.

   Failures clear as packages are removed: Shake in Task 5, SwiftyBeaver in Task 7. If the failing projects include `swift-composable-architecture` or any of its dependency projects listed above, run Task 13 Steps 1–7 inside Task 11, right after Task 11 Step 4, and skip them in Task 13. Strict mode resumes no later than the end of Task 13.
3. **Anything else** means Wait's own sources fail to compile. **Stop and ask the user.** This plan assumes the app code compiles.

- [ ] **Step 7 (manual: user, recommended): Seed parity data on the simulator** — SKIPPED (manual)

Skip this step if the baseline build failed. Otherwise, run this as one block:
```sh
UDID=$(xcrun simctl list devices available | awk '/-- iOS 27.0 --/{f=1;next} /^--/{f=0} f && /iPhone 17 \(/{match($0,/[0-9A-F-]{36}/); print substr($0,RSTART,RLENGTH); exit}')
echo "UDID=$UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator
xcodebuild -project /Users/ckai/code/Wait/Wait/Wait.xcodeproj -scheme Wait -destination "id=$UDID" \
  -derivedDataPath /Users/ckai/code/Wait/build/DerivedData -skipMacroValidation -skipPackagePluginValidation build 2>&1 | tail -1
xcrun simctl install "$UDID" /Users/ckai/code/Wait/build/DerivedData/Build/Products/Debug-iphonesimulator/Wait.app
xcrun simctl launch "$UDID" com.chenkai.wait
```
Expected: `UDID=<36-char id>`, `** BUILD SUCCEEDED **`, and `com.chenkai.wait: <pid>`.

Ask the user to add 2–3 stocks in the simulator, each with an expected price and one note, then quit the app. **Keep this simulator (don't erase it) until plan 01 is done.** Tasks 12 and 13 install over it to check that the watchlist is unchanged. Write the UDID into the log.

- [x] **Step 8: Fix the destinations in CLAUDE.md**

```sh
cd /Users/ckai/code/Wait && sed -i '' "s/-destination 'platform=iOS Simulator,name=iPhone 15'/-destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation/" CLAUDE.md \
  && grep -n "destination" CLAUDE.md
```
Expected: three lines, each ending in `name=iPhone 17,OS=27.0' -skipMacroValidation` (the third keeps its trailing ` \`). None of them mentions `iPhone 15`.

- [x] **Step 9: Commit**

```sh
cd /Users/ckai/code/Wait && git add docs/superpowers/plans/2026-11-22-wait-01-baseline-log.md CLAUDE.md && git commit -m "$(cat <<'EOF'
docs(plan01): record Xcode 27 baseline and fix simulator destinations

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: XcodeGen parity spec

This spec reproduces every live target with its bundle id, Info.plist, per-configuration entitlements, links and embeds. The six stale testables in the `Wait` scheme disappear automatically, because XcodeGen only writes test targets that exist.

**Files:**
- Create: `Wait/project.yml`
- Modify (generated): `Wait/Wait.xcodeproj/project.pbxproj`, `Wait/Wait.xcodeproj/xcshareddata/xcschemes/Wait.xcscheme`, `Wait/Wait.xcodeproj/xcshareddata/xcschemes/Color.xcscheme`

- [x] **Step 1: Write `Wait/project.yml`**

```yaml
# XcodeGen spec for Wait. Regenerate with `cd Wait && xcodegen generate`.
# Never hand-edit Wait.xcodeproj/project.pbxproj; edit this file instead.
name: Wait
options:
  bundleIdPrefix: com.ck
  deploymentTarget:
    iOS: "16.0"
    watchOS: "9.0"
  createIntermediateGroups: true
  developmentLanguage: en
settings:
  base:
    DEVELOPMENT_TEAM: 5WDN96EM72
    CODE_SIGN_STYLE: Automatic
    SWIFT_VERSION: "5.0"
    MARKETING_VERSION: "1.0"
    CURRENT_PROJECT_VERSION: "1"
packages:
  Alamofire:
    url: https://github.com/Alamofire/Alamofire
    from: 5.4.3
  ComposableArchitecture:
    url: https://github.com/pointfreeco/swift-composable-architecture
    from: 0.9.0
  Money:
    url: https://github.com/Flight-School/Money
    from: 1.3.0
  Shake:
    url: https://github.com/shakebugs/shake-ios
    from: 14.2.1
  SnapshotTesting:
    url: https://github.com/pointfreeco/swift-snapshot-testing
    from: 1.0.0
  SwiftyBeaver:
    url: https://github.com/SwiftyBeaver/SwiftyBeaver
    from: 1.9.4
  SwiftyJSON:
    url: https://github.com/SwiftyJSON/SwiftyJSON
    from: 5.0.1
targetTemplates:
  Framework:
    type: framework
    platform: iOS
    sources:
      - path: ${target_name}
        excludes:
          - "Info.plist"
          - "*.h"
          - "*.docc"
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.ck.${target_name}
        PRODUCT_NAME: "$(TARGET_NAME:c99extidentifier)"
        GENERATE_INFOPLIST_FILE: YES
        DEFINES_MODULE: YES
        SKIP_INSTALL: YES
        TARGETED_DEVICE_FAMILY: "1,2"
  UnitTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: ${target_name}
        excludes:
          - "__Snapshots__"
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.ck.${target_name}
        GENERATE_INFOPLIST_FILE: YES
        TARGETED_DEVICE_FAMILY: "1,2"
targets:
  Color:
    templates: [Framework]
  Size:
    templates: [Framework]
  UI:
    templates: [Framework]
    dependencies:
      - target: Color
  Logging:
    templates: [Framework]
    dependencies:
      - package: SwiftyBeaver
  Model:
    templates: [Framework]
    dependencies:
      - target: Color
      - package: Money
  Networking:
    templates: [Framework]
    dependencies:
      - target: Model
      - target: Logging
      - package: Alamofire
  CacheService:
    templates: [Framework]
    dependencies:
      - target: Model
      - target: Logging
  StockCharts:
    templates: [Framework]
    dependencies:
      - target: CacheService
      - target: Networking
      - target: Model
      - target: Color
      - target: Logging
      - package: Money
      - package: Alamofire
      - package: SwiftyJSON
  Checklist:
    templates: [Framework]
    dependencies:
      - target: CacheService
      - target: Size
      - target: Model
      - target: Logging
      - package: ComposableArchitecture
  ChecklistEditFeature:
    templates: [Framework]
    dependencies:
      - target: Logging
      - target: Model
      - package: ComposableArchitecture
  SettingsTab:
    templates: [Framework]
    dependencies:
      - target: ChecklistEditFeature
      - target: Model
      - package: ComposableArchitecture
  StockDetailsFeature:
    templates: [Framework]
    dependencies:
      - target: CacheService
      - target: Networking
      - target: Logging
      - target: Checklist
      - target: Size
      - target: Model
      - target: StockCharts
      - package: ComposableArchitecture
      - package: Alamofire
  ChecklistTests:
    templates: [UnitTests]
    settings:
      base:
        ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES: YES
    dependencies:
      - target: Checklist
  ChecklistEditFeatureTests:
    templates: [UnitTests]
    dependencies:
      - target: ChecklistEditFeature
      - target: Model
      - package: ComposableArchitecture
  StockDetailsFeatureTests:
    templates: [UnitTests]
    dependencies:
      - target: StockDetailsFeature
      - package: SnapshotTesting
  WaitWidgetExtension:
    type: app-extension
    platform: iOS
    sources:
      - path: WaitWidget
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.chenkai.wait.WaitWidget
        INFOPLIST_FILE: WaitWidget/Info.plist
        TARGETED_DEVICE_FAMILY: "1,2"
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME: WidgetBackground
        SKIP_INSTALL: YES
      configs:
        Release:
          CODE_SIGN_ENTITLEMENTS: WaitWidgetExtensionRelease.entitlements
    dependencies:
      - target: Model
      - target: Logging
      - target: Size
      - target: Networking
      - target: CacheService
      - package: Alamofire
      - package: SwiftyJSON
      - sdk: SwiftUI.framework
      - sdk: WidgetKit.framework
  WaitWatch:
    type: application
    platform: watchOS
    sources:
      - path: "WaitWatch Watch App"
      - path: Shared/Connectivity.swift
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: .watchkitapp
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_CFBundleDisplayName: WaitWatch
        INFOPLIST_KEY_UISupportedInterfaceOrientations: UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown
        INFOPLIST_KEY_WKCompanionAppBundleIdentifier: ""
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        DEVELOPMENT_ASSET_PATHS: '"WaitWatch Watch App/Preview Content"'
        ENABLE_PREVIEWS: YES
        SKIP_INSTALL: YES
        TARGETED_DEVICE_FAMILY: "4"
        LD_RUNPATH_SEARCH_PATHS: "$(inherited) @executable_path/Frameworks"
    dependencies:
      - package: Money
      - package: SwiftyJSON
      - package: Alamofire
  Wait:
    type: application
    platform: iOS
    sources:
      - path: Wait
      - path: Shared/Connectivity.swift
      - path: GoogleService-Info.plist
        buildPhase: resources
      - path: bitrise_configuration.plist
        buildPhase: resources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.chenkai.wait
        INFOPLIST_FILE: Wait/Info.plist
        TARGETED_DEVICE_FAMILY: "1"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        DEVELOPMENT_ASSET_PATHS: '"Wait/Preview Content"'
        ENABLE_PREVIEWS: YES
        ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES: YES
        SUPPORTED_PLATFORMS: iphoneos iphonesimulator
        SUPPORTS_MACCATALYST: NO
        SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO
        OTHER_LDFLAGS: ["-ObjC", "-l", "z", "-l", "c++"]
      configs:
        Debug:
          CODE_SIGN_ENTITLEMENTS: Wait/Wait.entitlements
        Release:
          CODE_SIGN_ENTITLEMENTS: Wait/WaitRelease.entitlements
    dependencies:
      - target: Color
      - target: UI
      - target: Model
      - target: Networking
      - target: Size
      - target: Logging
      - target: Checklist
      - target: ChecklistEditFeature
      - target: StockCharts
      - target: SettingsTab
      - target: StockDetailsFeature
      - target: CacheService
      - target: WaitWidgetExtension
      - package: Alamofire
      - package: SwiftyBeaver
      - package: SwiftyJSON
      - package: Shake
      - package: Money
      - package: ComposableArchitecture
aggregateTargets:
  Unused Code:
    buildScripts:
      - name: Periphery
        script: periphery scan --project Wait.xcodeproj --schemes Wait --targets Wait --format xcode
schemes:
  Wait:
    build:
      targets:
        Wait: all
    test:
      config: Debug
      gatherCoverageData: true
      targets:
        - ChecklistTests
        - ChecklistEditFeatureTests
        - StockDetailsFeatureTests
    run:
      config: Debug
    profile:
      config: Release
    analyze:
      config: Debug
    archive:
      config: Release
  Color:
    build:
      targets:
        Color: all
```

- [x] **Step 2: Generate the project**

```sh
cd /Users/ckai/code/Wait/Wait && xcodegen generate
```
Expected: the last line is `Created project at /Users/ckai/code/Wait/Wait/Wait.xcodeproj`.

- [x] **Step 3: Check that the package pins survived regeneration**

```sh
cd /Users/ckai/code/Wait && git status --short Wait/Wait.xcodeproj
```
Expected: ` M` for `project.pbxproj` and the two schemes, and no `D` line for `project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. If it shows as deleted, restore it:
```sh
cd /Users/ckai/code/Wait && git checkout -- Wait/Wait.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```
Then repeat this check after **every** `xcodegen generate` in later tasks.

- [ ] **Step 4: Compare targets and key settings with the old project** — NOT RUN (code-only; xcodebuild cannot resolve packages. Static parity check of the generated pbxproj done instead)

```sh
cd /Users/ckai/code/Wait/Wait && xcodebuild -list -project Wait.xcodeproj 2>/dev/null | sed -n '/Targets:/,/Build Configurations:/p'
```
Expected targets: CacheService, Checklist, ChecklistEditFeature, ChecklistEditFeatureTests, ChecklistTests, Color, Logging, Model, Networking, SettingsTab, Size, StockCharts, StockDetailsFeature, StockDetailsFeatureTests, UI, Unused Code, Wait, WaitWatch, WaitWidgetExtension. The output is sorted by XcodeGen's own order, so check membership, not order. The watch target is named `WaitWatch` (product `WaitWatch.app`), while its sources stay in the `WaitWatch Watch App` folder until plan 03 renames the folder. Later plans find it by grepping `project.yml` for `^  WaitWatch:`.

```sh
cd /Users/ckai/code/Wait/Wait && for c in Debug Release; do echo "== $c"; \
  xcodebuild -showBuildSettings -project Wait.xcodeproj -target Wait -configuration $c 2>/dev/null | grep -E " (PRODUCT_BUNDLE_IDENTIFIER|CODE_SIGN_ENTITLEMENTS|INFOPLIST_FILE|TARGETED_DEVICE_FAMILY) ="; \
  xcodebuild -showBuildSettings -project Wait.xcodeproj -target WaitWidgetExtension -configuration $c 2>/dev/null | grep -E " (PRODUCT_BUNDLE_IDENTIFIER|CODE_SIGN_ENTITLEMENTS) ="; done
```
Expected:
- **Debug:** the app shows `com.chenkai.wait`, `Wait/Wait.entitlements`, `Wait/Info.plist` and `1`. The widget shows `com.chenkai.wait.WaitWidget` and **no** `CODE_SIGN_ENTITLEMENTS` line.
- **Release:** the app shows `Wait/WaitRelease.entitlements`. The widget shows `WaitWidgetExtensionRelease.entitlements`.

- [ ] **Step 5: Build and test** — NOT RUN (code-only)

Run command B, then command C from the Prerequisites.
Expected in strict mode: `** BUILD SUCCEEDED **`, then `Executed 5 tests, with 0 failures` and `** TEST SUCCEEDED **`. Plain `xcodebuild test` now works without `-only-testing`, because the stale testables are gone. In red-baseline mode, apply Task 1 Step 6 rule 2.

- [x] **Step 6: Commit**

```sh
cd /Users/ckai/code/Wait && git add Wait/project.yml Wait/Wait.xcodeproj && git commit -m "$(cat <<'EOF'
chore(xcodegen): generate Wait.xcodeproj from project.yml with target parity

Drops six stale scheme testables that pointed at deleted targets.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Raise the floor to iOS 17 / watchOS 10 and prune the project

**Files:**
- Modify: `Wait/project.yml`, `Wait/Wait/Info.plist`, generated `Wait/Wait.xcodeproj`
- Delete (generated): `Wait/Wait.xcodeproj/xcshareddata/xcschemes/Color.xcscheme`

- [x] **Step 1: Raise the deployment targets in `Wait/project.yml`**

Replace:
```yaml
  deploymentTarget:
    iOS: "16.0"
    watchOS: "9.0"
```
with:
```yaml
  deploymentTarget:
    iOS: "17.0"
    watchOS: "10.0"
```

- [x] **Step 2: Remove the aggregate target and the `Color` scheme from `Wait/project.yml`**

Delete this whole block:
```yaml
aggregateTargets:
  Unused Code:
    buildScripts:
      - name: Periphery
        script: periphery scan --project Wait.xcodeproj --schemes Wait --targets Wait --format xcode
```
Then delete the last four lines of `schemes:`:
```yaml
  Color:
    build:
      targets:
        Color: all
```
Periphery can still be run by hand (Task 14 documents the command in CLAUDE.md).

- [x] **Step 3: Require arm64 instead of armv7**

```sh
cd /Users/ckai/code/Wait/Wait && plutil -replace UIRequiredDeviceCapabilities -json '["arm64"]' Wait/Info.plist \
  && plutil -extract UIRequiredDeviceCapabilities json -o - Wait/Info.plist
```
Expected: `["arm64"]`

- [ ] **Step 4: Regenerate and check the settings** — NOT RUN (code-only; `xcodegen generate` was run and the pbxproj was grepped for the deployment targets instead of `xcodebuild -showBuildSettings`)

```sh
cd /Users/ckai/code/Wait/Wait && xcodegen generate | tail -1 \
  && ls Wait.xcodeproj/xcshareddata/xcschemes \
  && xcodebuild -showBuildSettings -project Wait.xcodeproj -target Wait 2>/dev/null | grep " IPHONEOS_DEPLOYMENT_TARGET =" \
  && xcodebuild -showBuildSettings -project Wait.xcodeproj -target Checklist 2>/dev/null | grep " IPHONEOS_DEPLOYMENT_TARGET =" \
  && xcodebuild -showBuildSettings -project Wait.xcodeproj -target WaitWatch 2>/dev/null | grep " WATCHOS_DEPLOYMENT_TARGET ="
```
Expected:
```
Created project at /Users/ckai/code/Wait/Wait/Wait.xcodeproj
Wait.xcscheme
    IPHONEOS_DEPLOYMENT_TARGET = 17.0
    IPHONEOS_DEPLOYMENT_TARGET = 17.0
    WATCHOS_DEPLOYMENT_TARGET = 10.0
```
Then repeat the Package.resolved check from Task 2 Step 3.

- [ ] **Step 5: Build and test** — NOT RUN (code-only)

Run commands B and C. Expected: `** BUILD SUCCEEDED **` and `Executed 5 tests, with 0 failures`. New iOS 17 deprecation **warnings**, such as `onChange(of:perform:)`, are expected and fine.

- [x] **Step 6: Commit**

```sh
cd /Users/ckai/code/Wait && git add -A Wait/project.yml Wait/Wait/Info.plist Wait/Wait.xcodeproj && git commit -m "$(cat <<'EOF'
chore(xcodegen): raise floor to iOS 17 / watchOS 10, drop aggregate target and Color scheme

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Fix and embed the watch target

**Files:**
- Modify: `Wait/project.yml`, generated `Wait/Wait.xcodeproj` (adds the `WaitWatch.xcscheme`)

- [ ] **Step 1: Fix the watch bundle ids in `Wait/project.yml`**

In the `WaitWatch` target's `settings.base`, replace:
```yaml
        PRODUCT_BUNDLE_IDENTIFIER: .watchkitapp
```
with:
```yaml
        PRODUCT_BUNDLE_IDENTIFIER: com.chenkai.wait.watchkitapp
```
replace:
```yaml
        INFOPLIST_KEY_WKCompanionAppBundleIdentifier: ""
```
with these three lines. They mark the app as a single-target watch app that needs its iPhone companion:
```yaml
        INFOPLIST_KEY_WKApplication: YES
        INFOPLIST_KEY_WKCompanionAppBundleIdentifier: com.chenkai.wait
        INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp: NO
```

- [ ] **Step 2: Embed the watch app in the iOS app**

In the `Wait` target's `dependencies`, add this right after `- target: WaitWidgetExtension`. It is the same copy phase Xcode calls "Embed Watch Content":
```yaml
      - target: WaitWatch
        embed: true
        link: false
        codeSign: true
        copy:
          destination: productsDirectory
          subpath: "$(CONTENTS_FOLDER_PATH)/Watch"
```

- [ ] **Step 3: Add a `WaitWatch` scheme**

Append under `schemes:`:
```yaml
  WaitWatch:
    build:
      targets:
        WaitWatch: all
    run:
      config: Debug
    archive:
      config: Release
```

- [ ] **Step 4: Regenerate and build the watch scheme**

```sh
cd /Users/ckai/code/Wait/Wait && xcodegen generate | tail -1 && ls Wait.xcodeproj/xcshareddata/xcschemes
```
Expected: `Created project at …`, then `Wait.xcscheme` and `WaitWatch.xcscheme`. Repeat the Package.resolved check from Task 2 Step 3, then run command E.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Build the app and confirm the watch app is embedded with the right companion id**

```sh
xcodebuild -project /Users/ckai/code/Wait/Wait/Wait.xcodeproj -scheme Wait -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -derivedDataPath /Users/ckai/code/Wait/build/DerivedData -skipMacroValidation -skipPackagePluginValidation build 2>&1 | tail -1 \
  && ls "/Users/ckai/code/Wait/build/DerivedData/Build/Products/Debug-iphonesimulator/Wait.app/Watch" \
  && plutil -p "/Users/ckai/code/Wait/build/DerivedData/Build/Products/Debug-iphonesimulator/Wait.app/Watch/WaitWatch.app/Info.plist" \
     | grep -E '"(CFBundleIdentifier|WKApplication|WKCompanionAppBundleIdentifier|WKRunsIndependentlyOfCompanionApp)"'
```
Expected: the four lines below can come in any order.
```
** BUILD SUCCEEDED **
WaitWatch.app
  "CFBundleIdentifier" => "com.chenkai.wait.watchkitapp"
  "WKApplication" => true
  "WKCompanionAppBundleIdentifier" => "com.chenkai.wait"
  "WKRunsIndependentlyOfCompanionApp" => false
```
From now on, the app build fails if the watch fails to compile. That is intended (overview risk 17).

- [ ] **Step 6: Run the tests**

Run command C. Expected: `Executed 5 tests, with 0 failures`.

- [ ] **Step 7: Commit**

```sh
cd /Users/ckai/code/Wait && git add Wait/project.yml Wait/Wait.xcodeproj && git commit -m "$(cat <<'EOF'
fix(watch): valid watch bundle id, companion id, embed in app, add WaitWatch scheme

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Chunk 2: Secrets out of source, dead SDKs removed

### Task 5: Move secrets out of source and drop dead SDKs

This task removes the hard-coded Twelve Data and Alpha Vantage keys, Shake, the SwiftyBeaver cloud destination, the Bitrise APM token and the unused Firebase plist. The Twelve Data key moves to a gitignored xcconfig and reaches the code through Info.plist. Alpha Vantage `OVERVIEW` is Premium-only now, so the stats section keeps showing the empty overview it already shows in practice.

**Files:**
- Create: `scripts/check-secrets.sh`, `Wait/Config/Base.xcconfig`, `Wait/Config/Secrets.example.xcconfig`, `Wait/Config/Secrets.xcconfig` (gitignored), `Wait/WaitWatch Watch App/Info.plist`
- Modify: `.gitignore`, `Wait/project.yml`, `Wait/Wait/Info.plist`, `Wait/WaitWidget/Info.plist`, `Wait/Networking/URLDomain.swift`, `Wait/WaitWatch Watch App/PriceHistoryNetworkClient.swift`, `Wait/StockDetailsFeature/Network/StockOverviewNetworkClient.swift`, `Wait/StockDetailsFeature/View/StockDetailsView.swift:72`, `Wait/Wait/WaitApp.swift`, `Wait/Logging/Logging.swift`
- Delete: `Wait/GoogleService-Info.plist`, `Wait/bitrise_configuration.plist`

- [ ] **Step 1: Write the failing check: `scripts/check-secrets.sh`**

```bash
#!/usr/bin/env bash
#
# Fails (exit 1) when a tracked file looks like it contains a hard-coded credential.
# Prints file:line only, never the matched value. Run from anywhere inside the repo.
#
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

PATTERNS=(
  'name: "apikey", value: "[A-Za-z0-9]{8,}"'
  'clientId: "[A-Za-z0-9]{16,}"'
  'clientSecret: "[A-Za-z0-9]{16,}"'
  'appSecret: "[A-Za-z0-9]{8,}"'
  'encryptionKey: "[A-Za-z0-9]{8,}"'
  'APM_COLLECTOR_TOKEN'
  'AIza[0-9A-Za-z_-]{35}'
  '-----BEGIN ([A-Z]+ )?PRIVATE KEY-----'
  '_API_KEY *= *[A-Za-z0-9]{16,}'
)

status=0
for pattern in "${PATTERNS[@]}"; do
  matches=$(git grep -nIE -e "$pattern" -- . ':!docs' ':!scripts/check-secrets.sh' ':!**/Secrets.example.xcconfig' || true)
  if [[ -n "$matches" ]]; then
    echo "$matches" | cut -d: -f1-2
    status=1
  fi
done

if [[ "$status" -ne 0 ]]; then
  echo "check-secrets: possible credentials at the locations above" >&2
else
  echo "check-secrets: OK"
fi
exit "$status"
```
```sh
chmod +x /Users/ckai/code/Wait/scripts/check-secrets.sh
```

- [ ] **Step 2: Run it and watch it fail**

```sh
/Users/ckai/code/Wait/scripts/check-secrets.sh; echo "exit=$?"
```
Expected: `file:line` locations (no values) in at least these files: `Wait/Networking/URLDomain.swift`, `Wait/WaitWatch Watch App/PriceHistoryNetworkClient.swift`, `Wait/Wait/WaitApp.swift`, `Wait/Logging/Logging.swift`, `Wait/bitrise_configuration.plist` and `Wait/GoogleService-Info.plist`. Then `check-secrets: possible credentials …` and `exit=1`.

- [ ] **Step 3: Add the xcconfig files and ignore the real one**

`Wait/Config/Base.xcconfig`:
```
// Project-wide build settings for every configuration.
// Secrets are kept out of git: copy Secrets.example.xcconfig to Secrets.xcconfig and fill it in.
// The default below keeps builds working when Secrets.xcconfig is missing (quotes won't load).

TWELVE_DATA_API_KEY =

#include? "Secrets.xcconfig"
```
`Wait/Config/Secrets.example.xcconfig`:
```
// Copy to Secrets.xcconfig (gitignored) and replace the placeholder.
// Twelve Data is the stopgap quote provider until plan 04 moves market data to the Wait backend.
TWELVE_DATA_API_KEY = replace-with-your-twelve-data-key
```
```sh
cd /Users/ckai/code/Wait && cp Wait/Config/Secrets.example.xcconfig Wait/Config/Secrets.xcconfig \
  && printf '\n# Build-time secrets (see Wait/Config/Secrets.example.xcconfig)\nWait/Config/Secrets.xcconfig\n' >> .gitignore \
  && git check-ignore -v Wait/Config/Secrets.xcconfig
```
Expected: `.gitignore:<line>:Wait/Config/Secrets.xcconfig	Wait/Config/Secrets.xcconfig`

- [ ] **Step 4: Expose the key through Info.plist for the app, widget and watch**

```sh
cd /Users/ckai/code/Wait/Wait \
  && plutil -insert TwelveDataAPIKey -string '$(TWELVE_DATA_API_KEY)' Wait/Info.plist \
  && plutil -insert TwelveDataAPIKey -string '$(TWELVE_DATA_API_KEY)' WaitWidget/Info.plist \
  && cat > "WaitWatch Watch App/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>TwelveDataAPIKey</key>
	<string>$(TWELVE_DATA_API_KEY)</string>
</dict>
</plist>
EOF
plutil -lint "WaitWatch Watch App/Info.plist" Wait/Info.plist WaitWidget/Info.plist
```
Expected: three `: OK` lines.

- [ ] **Step 5: Update `Wait/project.yml`**

Make these edits:
1. After the `options:` block, add project-level config files:
   ```yaml
   configFiles:
     Debug: Config/Base.xcconfig
     Release: Config/Base.xcconfig
   ```
2. Under `packages:`, delete the `Shake:` entry (both of its lines).
3. In the `Wait` target:
   - delete `- package: Shake` from `dependencies`
   - delete the `OTHER_LDFLAGS: ["-ObjC", "-l", "z", "-l", "c++"]` line, which only Shake needed
   - replace its `sources:` list with:
     ```yaml
         sources:
           - path: Wait
           - path: Shared/Connectivity.swift
     ```
4. In the `WaitWatch` target's `settings.base`, add (keep `GENERATE_INFOPLIST_FILE: YES`, so the `INFOPLIST_KEY_*` values are merged in):
   ```yaml
           INFOPLIST_FILE: "WaitWatch Watch App/Info.plist"
   ```

- [ ] **Step 6: Read the key from Info.plist in `Wait/Networking/URLDomain.swift`**

Replace the whole file with:
```swift
// Created by kai_chen on 5/16/21.
// Copyright © 2021 Wait. All rights reserved.

import Foundation

// MARK: - URLDomain

public enum URLDomain: String {
  case twelveData = "https://api.twelvedata.com"
}

public extension URLDomain {
  var queryItems: [URLQueryItem] {
    switch self {
      case .twelveData:
        return [URLQueryItem(name: "apikey", value: APIKey.twelveData)]
    }
  }
}

// MARK: - APIKey

/// Provider keys injected at build time: `Config/Secrets.xcconfig` → build setting → Info.plist.
enum APIKey {
  static var twelveData: String {
    Bundle.main.object(forInfoDictionaryKey: "TwelveDataAPIKey") as? String ?? ""
  }
}
```

- [ ] **Step 7: Do the same in the watch copy**

In `Wait/WaitWatch Watch App/PriceHistoryNetworkClient.swift`, replace everything from line 94 (`// MARK: - URLDomain`) to the end of the file (line 112) with:
```swift
// MARK: - URLDomain

public enum URLDomain: String {
  case twelveData = "https://api.twelvedata.com"
}

public extension URLDomain {
  var queryItems: [URLQueryItem] {
    switch self {
      case .twelveData:
        return [URLQueryItem(name: "apikey", value: APIKey.twelveData)]
    }
  }
}

// MARK: - APIKey

/// Provider keys injected at build time: `Config/Secrets.xcconfig` → build setting → Info.plist.
enum APIKey {
  static var twelveData: String {
    Bundle.main.object(forInfoDictionaryKey: "TwelveDataAPIKey") as? String ?? ""
  }
}
```

- [ ] **Step 8: Replace the Alpha Vantage overview client**

Replace the whole of `Wait/StockDetailsFeature/Network/StockOverviewNetworkClient.swift` with:
```swift
//
// Created by: kai_chen on 6/6/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Combine
import Foundation
import Model

// MARK: - StockOverviewNetworkClient

protocol StockOverviewNetworkClient {
  func fetchStockOverview(stock: Stock) -> AnyPublisher<StockOverview, Error>
}

// MARK: - EmptyStockOverviewNetworkClient

/// Alpha Vantage's OVERVIEW endpoint is Premium-only, so the stats section shows the empty overview
/// until plan 04 serves fundamentals from the Wait backend.
final class EmptyStockOverviewNetworkClient: StockOverviewNetworkClient {
  func fetchStockOverview(stock: Stock) -> AnyPublisher<StockOverview, Error> {
    Just(StockOverview.empty)
      .setFailureType(to: Error.self)
      .eraseToAnyPublisher()
  }
}
```
In `Wait/StockDetailsFeature/View/StockDetailsView.swift`, replace line 72:
```swift
  @ObservedObject var stockOverviewDatSource = StockOverviewDataSource(networkClient: DefaultStockOverviewNetworkClient())
```
with:
```swift
  @ObservedObject var stockOverviewDatSource = StockOverviewDataSource(networkClient: EmptyStockOverviewNetworkClient())
```

- [ ] **Step 9: Remove Shake from `Wait/Wait/WaitApp.swift`**

Replace the whole file with:
```swift
// Created by kai_chen on 5/4/21.

import Color
import Logging
import SettingsTab
import SwiftUI

// MARK: - WaitApp

@main
struct WaitApp: App {
  // MARK: Lifecycle

  init() {
    Logger.setupLogger()
  }

  // MARK: Internal

  var body: some Scene {
    WindowGroup {
      TabView {
        MainView()
          .tabItem {
            Image(systemName: "house")
          }

        SettingsView()
          .tabItem {
            Image(systemName: "gearshape")
          }
      }
      .accentColor(.mint)
    }
  }
}
```

- [ ] **Step 10: Drop the SwiftyBeaver cloud destination**

Replace the whole of `Wait/Logging/Logging.swift` with this. SwiftyBeaver itself goes in Task 7.
```swift
//
// Created by: kai_chen on 8/22/21.
// Copyright © 2021 Wait. All rights reserved.
//

import Foundation
import SwiftyBeaver

public enum Logger {
  public static let shared = SwiftyBeaver.self

  public static func setupLogger() {
    shared.addDestination(ConsoleDestination())
    shared.addDestination(FileDestination())
  }
}
```

- [ ] **Step 11: Delete the unused credential plists**

```sh
cd /Users/ckai/code/Wait && git rm -q Wait/GoogleService-Info.plist Wait/bitrise_configuration.plist && git status --short | grep "^D"
```
Expected:
```
D  Wait/GoogleService-Info.plist
D  Wait/bitrise_configuration.plist
```

- [ ] **Step 12: Run the check again and watch it pass**

```sh
/Users/ckai/code/Wait/scripts/check-secrets.sh; echo "exit=$?"
```
Expected: `check-secrets: OK` and `exit=0`. If a location is still listed, fix it before continuing.

- [ ] **Step 13: Regenerate, build, test and confirm the key is injected**

```sh
cd /Users/ckai/code/Wait/Wait && xcodegen generate | tail -1
```
Repeat the Package.resolved check from Task 2 Step 3, then run commands B, C and E. Expected: `** BUILD SUCCEEDED **`, `Executed 5 tests, with 0 failures`, and `** BUILD SUCCEEDED **`.
```sh
xcodebuild -project /Users/ckai/code/Wait/Wait/Wait.xcodeproj -scheme Wait -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -derivedDataPath /Users/ckai/code/Wait/build/DerivedData -skipMacroValidation -skipPackagePluginValidation build 2>&1 | tail -1 \
  && /usr/libexec/PlistBuddy -c "Print :TwelveDataAPIKey" /Users/ckai/code/Wait/build/DerivedData/Build/Products/Debug-iphonesimulator/Wait.app/Info.plist \
  && /usr/libexec/PlistBuddy -c "Print :TwelveDataAPIKey" "/Users/ckai/code/Wait/build/DerivedData/Build/Products/Debug-iphonesimulator/Wait.app/Watch/WaitWatch.app/Info.plist" \
  && /usr/libexec/PlistBuddy -c "Print :WKCompanionAppBundleIdentifier" "/Users/ckai/code/Wait/build/DerivedData/Build/Products/Debug-iphonesimulator/Wait.app/Watch/WaitWatch.app/Info.plist"
```
Expected:
```
** BUILD SUCCEEDED **
replace-with-your-twelve-data-key
replace-with-your-twelve-data-key
com.chenkai.wait
```
The placeholder appears until the user adds a real key in Step 14. The last line proves the generated `INFOPLIST_KEY_*` values still merge into the watch plist.

- [ ] **Step 14 (manual: user): Rotate the leaked credentials**

All of these are in git history, and the repo may be public. Rewriting history isn't enough, so revoke or rotate each one:
1. **Twelve Data** (https://twelvedata.com/account/api-keys): regenerate the key. Put the new key in `Wait/Config/Secrets.xcconfig` as `TWELVE_DATA_API_KEY = <new key>`. Never commit that file.
2. **Alpha Vantage:** stop using the old key. The app no longer calls Alpha Vantage. Request a new key only if you need one elsewhere.
3. **Shake** (Shake dashboard → app settings): delete the app or rotate its client secret.
4. **SwiftyBeaver Platform:** delete the Wait app in the SwiftyBeaver Mac app or dashboard. Its app id, secret and encryption key were in `Wait/Logging/Logging.swift`.
5. **Bitrise APM:** regenerate or revoke the APM collector token in the Bitrise app settings.
6. **Firebase:** in the Firebase console, delete the iOS app, or restrict or delete its API key in Google Cloud Console → Credentials.

**This step is non-blocking.** Print the list for the user, then go straight on to Step 15 without waiting. Builds and tests work with the placeholder key, and the user can rotate the keys at any time.

- [ ] **Step 15: Commit**

```sh
cd /Users/ckai/code/Wait && git add .gitignore scripts/check-secrets.sh Wait/Config/Base.xcconfig Wait/Config/Secrets.example.xcconfig \
  "Wait/WaitWatch Watch App/Info.plist" "Wait/WaitWatch Watch App/PriceHistoryNetworkClient.swift" Wait/project.yml Wait/Wait.xcodeproj \
  Wait/Wait/Info.plist Wait/WaitWidget/Info.plist Wait/Networking/URLDomain.swift Wait/StockDetailsFeature/Network/StockOverviewNetworkClient.swift \
  Wait/StockDetailsFeature/View/StockDetailsView.swift Wait/Wait/WaitApp.swift Wait/Logging/Logging.swift \
  && git status --short | grep -c "Secrets.xcconfig$" ; git commit -m "$(cat <<'EOF'
chore(security): move Twelve Data key to gitignored xcconfig, remove Shake and dead credentials

- TWELVE_DATA_API_KEY comes from Wait/Config/Secrets.xcconfig via Info.plist
- Alpha Vantage OVERVIEW (Premium-only) replaced by an empty overview client
- Shake SDK, SwiftyBeaver cloud destination, Bitrise APM token and Firebase plist removed
- scripts/check-secrets.sh guards against new hard-coded credentials

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```
Expected: the `grep -c` prints `0`, which confirms `Secrets.xcconfig` is not staged. The commit then succeeds.

---

## Chunk 3: Moving the framework modules into WaitKit (leaf modules first)

**Rules for every task in this chunk:**
- Move files with `git mv`, so `git log --follow` keeps working.
- In a move commit, edit only `import` lines. That keeps rename similarity high.
- Every module moved here is a **legacy** target in Swift 5 language mode, with exactly the same public API as before.
- Package products are expected to link statically (SwiftPM's `automatic` library type), as TCA and Money already are today. This hasn't been verified for this exact mix of dynamic frameworks and package products. The real test is the runtime parity check at the end of Tasks 12 and 13.
- Some modules are still framework targets in this chunk, and each of those links its own copy of the package modules it uses. So until Task 12 finishes, a not-yet-moved framework can hold its own copy of a singleton such as `StockCache.shared`.
  - An edit made on a stock's detail screen may not show on the list until the next launch.
  - This is expected in the intermediate commits.
  - Behavior parity is checked at the end of Tasks 12 and 13, when everything links into the app binary once.
- Every commit in this chunk stages the whole `Wait/` folder. Just before committing, `git status --short | grep -v '^[RMAD] '` lists anything that isn't a staged rename, modification, addition or deletion. Expected: no output. Anything listed (for example `??`) is a stray file: remove or ignore it before you commit.
- In `Wait/project.yml`, a package product dependency is always written as:
  ```yaml
      - package: WaitKit
        product: <ProductName>
  ```
  with six spaces before `- package` and eight before `product`.

### Task 6: Create the WaitKit package with `DesignSystem` (Color + Size)

**Files:**
- Create: `Wait/Packages/WaitKit/Package.swift`
- Move: `Wait/Color/{Colors.swift,UIColor+CodeName.swift,UIColor+Hex.swift,UIColor+Theme.swift}` and `Wait/Size/Size.swift` → `Wait/Packages/WaitKit/Sources/DesignSystem/`
- Delete: `Wait/Color/Color.h`, `Wait/Color/Info.plist`, `Wait/Size/Size.h`, `Wait/Size/Info.plist`
- Modify: `.gitignore`, `Wait/project.yml`, and the import lines of:
  - `Wait/Model/Stock.swift`
  - `Wait/StockCharts/Stock/PriceHistoryDataSource.swift`
  - `Wait/Wait/WaitApp.swift`
  - `Wait/Wait/Waitlist/View/MainView.swift`
  - `Wait/Wait/Waitlist/View/SearchStockView.swift`
  - `Wait/Wait/Waitlist/View/StockCard.swift`
  - `Wait/Checklist/ChecklistListView.swift`
  - `Wait/StockDetailsFeature/View/StockChartView.swift`
  - `Wait/StockDetailsFeature/View/StockDetailsView.swift`
  - `Wait/StockDetailsFeature/View/StockExpectedPriceInputView.swift`
  - `Wait/WaitWidget/WaitWidget.swift`
  - `Wait/WaitWidget/WidgetStockRow.swift`

- [ ] **Step 1: Move the sources**

```sh
cd /Users/ckai/code/Wait/Wait && mkdir -p Packages/WaitKit/Sources/DesignSystem \
  && git mv Color/Colors.swift Color/UIColor+CodeName.swift Color/UIColor+Hex.swift Color/UIColor+Theme.swift Size/Size.swift Packages/WaitKit/Sources/DesignSystem/ \
  && git rm -q Color/Color.h Color/Info.plist Size/Size.h Size/Info.plist \
  && ls Packages/WaitKit/Sources/DesignSystem && ls -d Color Size 2>&1 | head -2
```
Expected: the five `.swift` files, then `ls: Color: No such file or directory` and `ls: Size: No such file or directory`.

- [ ] **Step 2: Write `Wait/Packages/WaitKit/Package.swift`**

```swift
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
```

- [ ] **Step 3: Ignore the package's own build output**

```sh
cd /Users/ckai/code/Wait && printf '\n# WaitKit standalone builds (the app resolves packages through the Xcode project)\nWait/Packages/WaitKit/.build/\nWait/Packages/WaitKit/.swiftpm/\nWait/Packages/WaitKit/Package.resolved\n' >> .gitignore \
  && tail -4 .gitignore
```

- [ ] **Step 4: Point the importers at `DesignSystem`**

```sh
cd /Users/ckai/code/Wait/Wait \
  && for f in $(grep -rlE '^import (Color|Size)$' --include='*.swift' Wait WaitWidget Model StockCharts Checklist StockDetailsFeature); do \
       sed -i '' -E 's/^import (Color|Size)$/import DesignSystem/' "$f"; done \
  && awk '!(/^import DesignSystem$/ && seen++)' Wait/Waitlist/View/MainView.swift > /tmp/MainView.swift \
  && mv /tmp/MainView.swift Wait/Waitlist/View/MainView.swift \
  && grep -rnE '^import (Color|Size)$' --include='*.swift' . ; grep -rl '^import DesignSystem$' --include='*.swift' . | wc -l
```
Expected: the first grep prints nothing, and the count prints `12`. `MainView.swift` imported both modules, and the `awk` keeps only its first `import DesignSystem`. The watch app has its own `Size.swift` copy and no `import Size`, so it isn't touched.

- [ ] **Step 5: Update `Wait/project.yml`**

1. At the top of `packages:`, add:
   ```yaml
     WaitKit:
       path: Packages/WaitKit
   ```
2. Delete the `Color:` and `Size:` target entries (two lines each: the name and `templates: [Framework]`).
3. In `UI`, delete its whole `dependencies:` block, because UI doesn't import Color.
4. In `Model` and `StockCharts`, replace `      - target: Color` with the DesignSystem product entry.
5. In `Checklist`, `StockDetailsFeature` and `WaitWidgetExtension`, replace `      - target: Size` with the DesignSystem product entry.
6. In `Wait`, delete `      - target: Color` and replace `      - target: Size` with the DesignSystem product entry.

The DesignSystem product entry is:
```yaml
      - package: WaitKit
        product: DesignSystem
```
Check it:
```sh
cd /Users/ckai/code/Wait/Wait && grep -nE "target: (Color|Size)$" project.yml; grep -c "product: DesignSystem" project.yml
```
Expected: nothing from the first grep, then `6`.

- [ ] **Step 6: Regenerate and build the package on its own**

```sh
cd /Users/ckai/code/Wait/Wait && xcodegen generate | tail -1 \
  && cd Packages/WaitKit && xcodebuild -list 2>/dev/null | sed -n '/Schemes:/,$p' \
  && xcodebuild build -scheme WaitKit -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation 2>&1 | tail -1
```
Expected: `Created project at …`, then `Schemes:` followed by the single scheme `WaitKit`, then `** BUILD SUCCEEDED **`. While the package has one product, Xcode names its only scheme after the package. Once Task 7 adds a second product, the schemes become `DesignSystem`, `Logging` and `WaitKit-Package`. Then repeat the Package.resolved check from Task 2 Step 3.

- [ ] **Step 7: Build and test the app**

Run commands B, C and E. Expected: `** BUILD SUCCEEDED **`, `Executed 5 tests, with 0 failures`, and `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```sh
cd /Users/ckai/code/Wait && git add -A .gitignore Wait && git status --short | grep -v '^[RMAD] ' ; git commit -m "$(cat <<'EOF'
refactor(waitkit): add local WaitKit package and move Color + Size into DesignSystem

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Move `Logging` and replace SwiftyBeaver with an `os.Logger` shim

The existing call sites use `Logger.shared.verbose(...)` 8 times and `Logger.shared.error(...)` 16 times. They keep compiling unchanged.

**Name clash:** Apple's `os` module also declares `Logger`. Inside the `Logging` module, an unqualified `Logger` resolves to the module's own enum, so the shim always spells Apple's type `os.Logger`. Call sites import `Logging`, not `os`, so they see only the shim.

**Files:**
- Move: `Wait/Logging/Logging.swift` → `Wait/Packages/WaitKit/Sources/Logging/LegacyLogger.swift` (rewritten)
- Delete: `Wait/Logging/Info.plist`, `Wait/Logging/Logging.h`
- Modify: `Wait/Packages/WaitKit/Package.swift`, `Wait/project.yml`, `Wait/Wait/WaitApp.swift`

- [ ] **Step 1: Move the file**

```sh
cd /Users/ckai/code/Wait/Wait && mkdir -p Packages/WaitKit/Sources/Logging \
  && git mv Logging/Logging.swift Packages/WaitKit/Sources/Logging/LegacyLogger.swift \
  && git rm -q Logging/Info.plist Logging/Logging.h
```

- [ ] **Step 2: Replace the contents of `Wait/Packages/WaitKit/Sources/Logging/LegacyLogger.swift`**

```swift
//
// Created by: kai_chen on 8/22/21.
// Copyright © 2021 Wait. All rights reserved.
//

import os

// MARK: - Logger

/// Legacy facade that keeps the existing `Logger.shared.verbose(...)` / `Logger.shared.error(...)` call sites
/// compiling after SwiftyBeaver's removal. Messages go to unified logging (subsystem `com.chenkai.wait`,
/// category `legacy`). Plan 02 deletes this file in favor of `Log` categories.
///
/// Inside this module `Logger` names this enum, so Apple's type is always written `os.Logger`.
public enum Logger {
  public static let shared = LegacyLogger()
}

// MARK: - LegacyLogger

public struct LegacyLogger: Sendable {
  // MARK: Public

  public func verbose(_ message: @autoclosure () -> Any, file: StaticString = #fileID, line: UInt = #line) {
    let text = Self.render(message(), file: file, line: line)
    logger.debug("\(text, privacy: .public)")
  }

  public func error(_ message: @autoclosure () -> Any, file: StaticString = #fileID, line: UInt = #line) {
    let text = Self.render(message(), file: file, line: line)
    logger.error("\(text, privacy: .public)")
  }

  // MARK: Internal

  static func render(_ message: Any, file: StaticString, line: UInt) -> String {
    "[\(file):\(line)] \(message)"
  }

  // MARK: Private

  private let logger = os.Logger(subsystem: "com.chenkai.wait", category: "legacy")
}
```

- [ ] **Step 3: Drop the logger setup from `Wait/Wait/WaitApp.swift`**

Replace the whole file with:
```swift
// Created by kai_chen on 5/4/21.

import DesignSystem
import SettingsTab
import SwiftUI

// MARK: - WaitApp

@main
struct WaitApp: App {
  var body: some Scene {
    WindowGroup {
      TabView {
        MainView()
          .tabItem {
            Image(systemName: "house")
          }

        SettingsView()
          .tabItem {
            Image(systemName: "gearshape")
          }
      }
      .accentColor(.mint)
    }
  }
}
```

- [ ] **Step 4: Replace `Wait/Packages/WaitKit/Package.swift` with this version, which adds `Logging` in Swift 6 mode**

```swift
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
    .library(name: "Logging", targets: ["Logging"]),
  ],
  targets: [
    .target(name: "DesignSystem", swiftSettings: legacySettings),
    .target(name: "Logging"),
  ],
  swiftLanguageModes: [.v6]
)
```

- [ ] **Step 5: Update `Wait/project.yml`**

1. Delete the `Logging:` target entry, all four lines:
   ```yaml
     Logging:
       templates: [Framework]
       dependencies:
         - package: SwiftyBeaver
   ```
2. Delete the `SwiftyBeaver:` entry under `packages:`, and delete `      - package: SwiftyBeaver` from the `Wait` target.
3. Replace every `      - target: Logging` with:
   ```yaml
      - package: WaitKit
        product: Logging
   ```
   This applies in `Networking`, `CacheService`, `StockCharts`, `Checklist`, `ChecklistEditFeature`, `StockDetailsFeature`, `WaitWidgetExtension` and `Wait`.

Check it:
```sh
cd /Users/ckai/code/Wait/Wait && grep -nE "SwiftyBeaver|target: Logging$" project.yml; grep -c "product: Logging" project.yml; grep -rn "SwiftyBeaver" --include='*.swift' . | head -1
```
Expected: no output from the first and last greps, and `8` in between.

- [ ] **Step 6: Regenerate, then build and test**

```sh
cd /Users/ckai/code/Wait/Wait && xcodegen generate | tail -1 \
  && cd Packages/WaitKit && xcodebuild -list 2>/dev/null | sed -n '/Schemes:/,$p' \
  && xcodebuild build -scheme WaitKit-Package -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation 2>&1 | tail -1
```
Expected: `Created project at …`. The schemes list now includes `WaitKit-Package`, `DesignSystem` and `Logging`. Then `** BUILD SUCCEEDED **`.
Repeat the Package.resolved check from Task 2 Step 3, then run commands B, C and E. Expected: `** BUILD SUCCEEDED **`, `Executed 5 tests, with 0 failures`, and `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```sh
cd /Users/ckai/code/Wait && git add -A Wait && git status --short | grep -v '^[RMAD] ' ; git commit -m "$(cat <<'EOF'
refactor(waitkit): move Logging into WaitKit and replace SwiftyBeaver with an os.Logger shim

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Move the legacy `Model`

**Files:**
- Move: `Wait/Model/*.swift` (11 files) → `Wait/Packages/WaitKit/Sources/Model/`
- Delete: `Wait/Model/Info.plist`, `Wait/Model/Model.h`
- Modify: `Wait/Packages/WaitKit/Package.swift`, `Wait/project.yml`

- [ ] **Step 1: Move the sources**

```sh
cd /Users/ckai/code/Wait/Wait && mkdir -p Packages/WaitKit/Sources/Model \
  && git mv Model/*.swift Packages/WaitKit/Sources/Model/ \
  && git rm -q Model/Info.plist Model/Model.h \
  && ls Packages/WaitKit/Sources/Model | wc -l
```
Expected: `11`

- [ ] **Step 2: Replace `Wait/Packages/WaitKit/Package.swift` (adds Money, pinned exactly, and `Model`)**

```swift
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
  static let money = Self.product(name: "Money", package: "Money")
}

let package = Package(
  name: "WaitKit",
  defaultLocalization: "en",
  platforms: [.iOS(.v17), .watchOS(.v10)],
  products: [
    .library(name: "DesignSystem", targets: ["DesignSystem"]),
    .library(name: "Logging", targets: ["Logging"]),
    .library(name: "Model", targets: ["Model"]),
  ],
  dependencies: [
    // Legacy only — removed at the plan 02 cutover.
    .package(url: "https://github.com/Flight-School/Money", exact: "1.3.0"),
  ],
  targets: [
    .target(name: "DesignSystem", swiftSettings: legacySettings),
    .target(name: "Logging"),
    .target(name: "Model", dependencies: ["DesignSystem", .money], swiftSettings: legacySettings),
  ],
  swiftLanguageModes: [.v6]
)
```

- [ ] **Step 3: Update `Wait/project.yml`**

1. Delete the whole `Model:` target entry. After Task 6 it reads:
   ```yaml
     Model:
       templates: [Framework]
       dependencies:
         - package: WaitKit
           product: DesignSystem
         - package: Money
   ```
2. Replace every `      - target: Model` with:
   ```yaml
      - package: WaitKit
        product: Model
   ```
   This applies in `Networking`, `CacheService`, `StockCharts`, `Checklist`, `ChecklistEditFeature`, `SettingsTab`, `StockDetailsFeature`, `ChecklistEditFeatureTests`, `WaitWidgetExtension` and `Wait`.
3. Add the same Model product entry to the `dependencies` of `ChecklistTests` and `StockDetailsFeatureTests`. Both import `Model`. While Model was a dynamic framework they got it through autolinking, but a static product must be declared.

Check it:
```sh
cd /Users/ckai/code/Wait/Wait && grep -n "target: Model$" project.yml; grep -c "product: Model" project.yml
```
Expected: no output, then `12`.

- [ ] **Step 4: Regenerate, then build and test**

```sh
cd /Users/ckai/code/Wait/Wait && xcodegen generate | tail -1 \
  && cd Packages/WaitKit && xcodebuild build -scheme WaitKit-Package -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation 2>&1 | tail -1
```
Expected: `Created project at …` and `** BUILD SUCCEEDED **`. Repeat the Package.resolved check from Task 2 Step 3, then run commands B, C and E with the same expectations as Task 7 Step 6.

If Money's manifest is rejected (`Invalid manifest` naming `Money`), stop and ask the user. Plan 02 removes Money, and vendoring it here would be throwaway work.

- [ ] **Step 5: Commit**

```sh
cd /Users/ckai/code/Wait && git add -A Wait && git status --short | grep -v '^[RMAD] ' ; git commit -m "$(cat <<'EOF'
refactor(waitkit): move legacy Model into WaitKit (Swift 5 mode, Money pinned 1.3.0)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Move `CacheService` and `Networking`

**Files:**
- Move: `Wait/CacheService/{Cache,StockCache,Storage}.swift` → `Wait/Packages/WaitKit/Sources/CacheService/`
- Move: `Wait/Networking/{NetworkingURLBuilder,StockCurrentQuoteNetworkClient,URLDomain}.swift` → `Wait/Packages/WaitKit/Sources/Networking/`
- Delete: `Wait/Networking/Info.plist`, `Wait/Networking/Networking.h`
- Modify: `Wait/Packages/WaitKit/Sources/Networking/StockCurrentQuoteNetworkClient.swift` (drop the unused `import Alamofire`), `Wait/Packages/WaitKit/Package.swift`, `Wait/project.yml`

- [ ] **Step 1: Move the sources and drop the unused Alamofire import**

```sh
cd /Users/ckai/code/Wait/Wait && mkdir -p Packages/WaitKit/Sources/CacheService Packages/WaitKit/Sources/Networking \
  && git mv CacheService/Cache.swift CacheService/StockCache.swift CacheService/Storage.swift Packages/WaitKit/Sources/CacheService/ \
  && git mv Networking/NetworkingURLBuilder.swift Networking/StockCurrentQuoteNetworkClient.swift Networking/URLDomain.swift Packages/WaitKit/Sources/Networking/ \
  && git rm -q Networking/Info.plist Networking/Networking.h \
  && sed -i '' '/^import Alamofire$/d' Packages/WaitKit/Sources/Networking/StockCurrentQuoteNetworkClient.swift \
  && grep -c "^import" Packages/WaitKit/Sources/Networking/StockCurrentQuoteNetworkClient.swift
```
Expected: `4` (Combine, Foundation, Logging, Model).

- [ ] **Step 2: Replace `Wait/Packages/WaitKit/Package.swift`**

```swift
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
  static let money = Self.product(name: "Money", package: "Money")
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
  ],
  dependencies: [
    // Legacy only — removed at the plan 02 cutover.
    .package(url: "https://github.com/Flight-School/Money", exact: "1.3.0"),
  ],
  targets: [
    .target(name: "DesignSystem", swiftSettings: legacySettings),
    .target(name: "Logging"),
    .target(name: "Model", dependencies: ["DesignSystem", .money], swiftSettings: legacySettings),
    .target(name: "CacheService", dependencies: ["Model", "Logging"], swiftSettings: legacySettings),
    .target(name: "Networking", dependencies: ["Model", "Logging"], swiftSettings: legacySettings),
  ],
  swiftLanguageModes: [.v6]
)
```

- [ ] **Step 3: Update `Wait/project.yml`**

1. Delete the `Networking:` and `CacheService:` target entries completely: name, `templates`, and every dependency line.
2. Replace every `      - target: CacheService` with the CacheService product entry, in `StockCharts`, `Checklist`, `StockDetailsFeature`, `WaitWidgetExtension` and `Wait`:
   ```yaml
      - package: WaitKit
        product: CacheService
   ```
3. Replace every `      - target: Networking` with the Networking product entry, in `StockCharts`, `StockDetailsFeature`, `WaitWidgetExtension` and `Wait`:
   ```yaml
      - package: WaitKit
        product: Networking
   ```

Check it:
```sh
cd /Users/ckai/code/Wait/Wait && grep -nE "target: (CacheService|Networking)$" project.yml; grep -c "product: CacheService" project.yml; grep -c "product: Networking" project.yml
```
Expected: no output, then `5`, then `4`.

- [ ] **Step 4: Regenerate, then build and test**

```sh
cd /Users/ckai/code/Wait/Wait && xcodegen generate | tail -1 \
  && cd Packages/WaitKit && xcodebuild build -scheme WaitKit-Package -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation 2>&1 | tail -1
```
Expected: `Created project at …` and `** BUILD SUCCEEDED **`. Repeat the Package.resolved check from Task 2 Step 3, then run commands B, C and E with the same expectations as Task 7 Step 6.

- [ ] **Step 5: Commit**

```sh
cd /Users/ckai/code/Wait && git add -A Wait && git status --short | grep -v '^[RMAD] ' ; git commit -m "$(cat <<'EOF'
refactor(waitkit): move CacheService and Networking into WaitKit

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Move `StockCharts`

**Files:**
- Move: `Wait/StockCharts/Stock/{ChartCache,ChartHighlightMarker,ChartViewDataSource,PriceHistoryDataSource,PriceHistoryNetworkClient,TimeSection}.swift` → `Wait/Packages/WaitKit/Sources/StockCharts/`
- Delete: `Wait/StockCharts/StockCharts.h`
- Modify:
  - `Wait/Packages/WaitKit/Package.swift`: adds Alamofire 5.5.0 and SwiftyJSON 5.0.1, pinned exactly
  - `Wait/project.yml`
  - `Wait/Wait/Waitlist/View/MainView.swift`: drop the unused `import Alamofire` and `import Money`
  - `Wait/Wait/Waitlist/View/SearchStockView.swift`: drop the unused `import Alamofire`

- [ ] **Step 1: Move the sources and drop the unused app imports**

```sh
cd /Users/ckai/code/Wait/Wait && mkdir -p Packages/WaitKit/Sources/StockCharts \
  && git mv StockCharts/Stock/ChartCache.swift StockCharts/Stock/ChartHighlightMarker.swift StockCharts/Stock/ChartViewDataSource.swift \
            StockCharts/Stock/PriceHistoryDataSource.swift StockCharts/Stock/PriceHistoryNetworkClient.swift StockCharts/Stock/TimeSection.swift \
            Packages/WaitKit/Sources/StockCharts/ \
  && git rm -q StockCharts/StockCharts.h \
  && sed -i '' -E '/^import (Alamofire|Money)$/d' Wait/Waitlist/View/MainView.swift Wait/Waitlist/View/SearchStockView.swift \
  && grep -rnE '^import (Alamofire|SwiftyJSON|Money)$' --include='*.swift' Wait WaitWidget StockDetailsFeature
```
Expected: exactly these three lines, in any order:
```
StockDetailsFeature/Models/ValuationData.swift:<n>:import Money
StockDetailsFeature/View/ExpectedStockPriceChart.swift:<n>:import Money
StockDetailsFeature/View/StockExpectedPriceInputView.swift:<n>:import Money
```
The app and widget no longer import Alamofire, SwiftyJSON or Money. Inside the package, `Model` and `StockCharts` import them. Outside the package, only these three `StockDetailsFeature` files (which still get Money through the `Model` product) and the watch app do. Task 12 moves the three files into `LegacyStockDetails`, which declares `.money` explicitly.

- [ ] **Step 2: Replace `Wait/Packages/WaitKit/Package.swift`**

```swift
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
```

- [ ] **Step 3: Update `Wait/project.yml`**

1. Delete the `StockCharts:` target entry completely.
2. Replace every `      - target: StockCharts` with the StockCharts product entry, in `StockDetailsFeature` and `Wait`:
   ```yaml
      - package: WaitKit
        product: StockCharts
   ```
3. Delete `      - package: Alamofire`, `      - package: SwiftyJSON` and `      - package: Money` from the `Wait` target.
4. Delete `      - package: Alamofire` and `      - package: SwiftyJSON` from `WaitWidgetExtension`.
5. Delete `      - package: Alamofire` from `StockDetailsFeature`. Its only Alamofire import went away in Task 5.

Check it:
```sh
cd /Users/ckai/code/Wait/Wait && grep -n "target: StockCharts$" project.yml; grep -nE "package: (Alamofire|SwiftyJSON|Money)$" project.yml
```
Expected: no output from the first grep. The second prints exactly three lines, all inside the `WaitWatch` target.

- [ ] **Step 4: Regenerate, then build and test**

```sh
cd /Users/ckai/code/Wait/Wait && xcodegen generate | tail -1 \
  && cd Packages/WaitKit && xcodebuild build -scheme WaitKit-Package -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation 2>&1 | tail -1
```
Expected: `Created project at …` and `** BUILD SUCCEEDED **`. Repeat the Package.resolved check from Task 2 Step 3, then run commands B, C and E with the same expectations as Task 7 Step 6.

- [ ] **Step 5: Commit**

```sh
cd /Users/ckai/code/Wait && git add -A Wait && git status --short | grep -v '^[RMAD] ' ; git commit -m "$(cat <<'EOF'
refactor(waitkit): move StockCharts into WaitKit; app and widget stop linking Alamofire/SwiftyJSON/Money

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Chunk 4: Checklist modules and the three-target project

### Task 11: Move `Checklist`, `ChecklistEditFeature` and their tests

TCA stays at **0.31.0, pinned exactly**, so this commit only moves files. `StockDetailsFeature` and `SettingsTab` are still framework targets, and they keep using the project-level TCA package. The local package's exact pin and the project's `from: 0.9.0` resolve to the same 0.31.0 checkout.

**Files:**
- Move:
  - `Wait/Checklist/{Checklist,ChecklistListTCA,ChecklistListView,ChecklistStorage}.swift` → `Wait/Packages/WaitKit/Sources/Checklist/`
  - `Wait/ChecklistEditFeature/{ChecklistDataManager,ChecklistEditTCA,ChecklistEditView}.swift` → `Wait/Packages/WaitKit/Sources/ChecklistEditFeature/`
  - `Wait/ChecklistTests/ChecklistListTests.swift` → `Wait/Packages/WaitKit/Tests/ChecklistTests/`
  - `Wait/ChecklistEditFeatureTests/{ChecklistEditFeatureTests,MockChecklistDataManager}.swift` → `Wait/Packages/WaitKit/Tests/ChecklistEditFeatureTests/`
- Delete: `Wait/Checklist/Checklist.docc` (an unedited template), `Wait/ChecklistEditFeature/ChecklistEditFeature.h`
- Modify: `Wait/Packages/WaitKit/Package.swift`, `Wait/project.yml`

- [ ] **Step 1: Move the sources and tests**

```sh
cd /Users/ckai/code/Wait/Wait && mkdir -p Packages/WaitKit/Sources/Checklist Packages/WaitKit/Sources/ChecklistEditFeature \
       Packages/WaitKit/Tests/ChecklistTests Packages/WaitKit/Tests/ChecklistEditFeatureTests \
  && git mv Checklist/Checklist.swift Checklist/ChecklistListTCA.swift Checklist/ChecklistListView.swift Checklist/ChecklistStorage.swift \
            Packages/WaitKit/Sources/Checklist/ \
  && git mv ChecklistEditFeature/ChecklistDataManager.swift ChecklistEditFeature/ChecklistEditTCA.swift ChecklistEditFeature/ChecklistEditView.swift \
            Packages/WaitKit/Sources/ChecklistEditFeature/ \
  && git mv ChecklistTests/ChecklistListTests.swift Packages/WaitKit/Tests/ChecklistTests/ \
  && git mv ChecklistEditFeatureTests/ChecklistEditFeatureTests.swift ChecklistEditFeatureTests/MockChecklistDataManager.swift \
            Packages/WaitKit/Tests/ChecklistEditFeatureTests/ \
  && git rm -rq Checklist/Checklist.docc ChecklistEditFeature/ChecklistEditFeature.h \
  && ls -d Checklist ChecklistEditFeature ChecklistTests ChecklistEditFeatureTests 2>&1 | grep -c "No such file"
```
Expected: `4`

- [ ] **Step 2: Replace `Wait/Packages/WaitKit/Package.swift`**

This adds TCA 0.31.0, pinned exactly, plus the two modules and their test targets:
```swift
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
    .library(name: "DesignSystem", targets: ["DesignSystem"]),
    .library(name: "Logging", targets: ["Logging"]),
    .library(name: "Model", targets: ["Model"]),
    .library(name: "CacheService", targets: ["CacheService"]),
    .library(name: "Networking", targets: ["Networking"]),
    .library(name: "StockCharts", targets: ["StockCharts"]),
    .library(name: "Checklist", targets: ["Checklist"]),
    .library(name: "ChecklistEditFeature", targets: ["ChecklistEditFeature"]),
  ],
  dependencies: [
    // Task 13 of plan 01 upgrades this to 1.26.2.
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "0.31.0"),
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
    .target(
      name: "Checklist",
      dependencies: ["CacheService", "DesignSystem", "Model", "Logging", .tca],
      swiftSettings: legacySettings
    ),
    .target(name: "ChecklistEditFeature", dependencies: ["Logging", "Model", .tca], swiftSettings: legacySettings),
    .testTarget(name: "ChecklistTests", dependencies: ["Checklist", "Model", .tca], swiftSettings: legacySettings),
    .testTarget(name: "ChecklistEditFeatureTests", dependencies: ["ChecklistEditFeature", "Model", .tca], swiftSettings: legacySettings),
  ],
  swiftLanguageModes: [.v6]
)
```

- [ ] **Step 3: Update `Wait/project.yml`**

1. Delete the `Checklist:`, `ChecklistEditFeature:`, `ChecklistTests:` and `ChecklistEditFeatureTests:` target entries completely.
2. In `SettingsTab`, replace `      - target: ChecklistEditFeature` with:
   ```yaml
      - package: WaitKit
        product: ChecklistEditFeature
   ```
3. In `StockDetailsFeature`, replace `      - target: Checklist` with:
   ```yaml
      - package: WaitKit
        product: Checklist
   ```
4. In `Wait`, replace both `      - target: Checklist` and `      - target: ChecklistEditFeature` with the matching product entries.
5. In `schemes.Wait.test.targets`, keep only `- StockDetailsFeatureTests`.

Check it:
```sh
cd /Users/ckai/code/Wait/Wait && grep -nE "target: Checklist(EditFeature)?$|^  Checklist(Tests|EditFeature|EditFeatureTests)?:$" project.yml; grep -A3 "    test:" project.yml
```
Expected: no output from the first grep, and the `test:` block lists only `- StockDetailsFeatureTests`.

- [ ] **Step 4: Regenerate and run the moved tests from the package**

```sh
cd /Users/ckai/code/Wait/Wait && xcodegen generate | tail -1
```
Repeat the Package.resolved check from Task 2 Step 3, then run command D.
Expected: `Executed 4 tests, with 0 failures` and `** TEST SUCCEEDED **`.

If you're in red-baseline mode, save command D's full output (`… > /tmp/wait-task11-test.log 2>&1`) and run Task 1 Step 6 check (i) on it. If any failing project is `swift-composable-architecture` or one of its dependency projects (`swift-custom-dump`, `swift-case-paths`, `combine-schedulers`, `xctest-dynamic-overlay`, `swift-identified-collections`, `swift-collections`), TCA 0.31.0 can't build here. In that case run Task 13 Steps 1–7 now, then come back to Step 5.

- [ ] **Step 5: Build the app and run the remaining app-scheme test**

Run commands B, C and E. Expected: `** BUILD SUCCEEDED **`, then `Executed 1 test, with 0 failures`, then `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```sh
cd /Users/ckai/code/Wait && git add -A Wait && git status --short | grep -v '^[RMAD] ' ; git commit -m "$(cat <<'EOF'
refactor(waitkit): move Checklist and ChecklistEditFeature (with tests) into WaitKit

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: Move `StockDetailsFeature` (as `LegacyStockDetails`) and `SettingsTab`, and delete `UI`

After this task the Xcode project has three targets. Every module links into the app binary exactly once, so the transitional duplicate copies from Chunk 3 are gone.

The module is renamed so that plan 02 can introduce the new `StockDetailsFeature` TCA module (overview §3.1).

**Files:**
- Move: `Wait/StockDetailsFeature/{Datasource,Models,Network,View}/` → `Wait/Packages/WaitKit/Sources/LegacyStockDetails/`
- Move: `Wait/SettingsTab/SettingsView.swift` → `Wait/Packages/WaitKit/Sources/SettingsTab/`
- Delete:
  - `Wait/StockDetailsFeature/StockDetailsFeature.h`, `Wait/SettingsTab/SettingsTab.h`
  - `Wait/UI/`: an unused UIKit counter; nothing imports it
  - `Wait/StockDetailsFeatureTests/`: its one test compares `.empty` to the initial `.empty` without waiting, and the `__Snapshots__` PNG has no test
- Modify:
  - `Wait/Packages/WaitKit/Package.swift`
  - `Wait/project.yml`: full rewrite
  - `Wait/Wait/Waitlist/View/MainView.swift` and `Wait/Wait/Waitlist/View/SearchStockView.swift`: import lines only

- [ ] **Step 1: Move, delete and rename the import**

```sh
cd /Users/ckai/code/Wait/Wait && mkdir -p Packages/WaitKit/Sources/LegacyStockDetails Packages/WaitKit/Sources/SettingsTab \
  && git mv StockDetailsFeature/Datasource StockDetailsFeature/Models StockDetailsFeature/Network StockDetailsFeature/View \
            Packages/WaitKit/Sources/LegacyStockDetails/ \
  && git mv SettingsTab/SettingsView.swift Packages/WaitKit/Sources/SettingsTab/ \
  && git rm -rq StockDetailsFeature/StockDetailsFeature.h SettingsTab/SettingsTab.h UI StockDetailsFeatureTests \
  && sed -i '' 's/^import StockDetailsFeature$/import LegacyStockDetails/' Wait/Waitlist/View/MainView.swift Wait/Waitlist/View/SearchStockView.swift \
  && grep -rn "StockDetailsFeature" --include='*.swift' . ; find Packages/WaitKit/Sources/LegacyStockDetails -name '*.swift' | wc -l
```
Expected: no output from the grep, then `8`.

- [ ] **Step 2: Replace `Wait/Packages/WaitKit/Package.swift`**

```swift
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
  ],
  dependencies: [
    // Task 13 of plan 01 upgrades this to 1.26.2.
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "0.31.0"),
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
    .testTarget(name: "ChecklistTests", dependencies: ["Checklist", "Model", .tca], swiftSettings: legacySettings),
    .testTarget(name: "ChecklistEditFeatureTests", dependencies: ["ChecklistEditFeature", "Model", .tca], swiftSettings: legacySettings),
  ],
  swiftLanguageModes: [.v6]
)
```

- [ ] **Step 3: Replace `Wait/project.yml` with the three-target spec**

```yaml
# XcodeGen spec for Wait. Regenerate with `cd Wait && xcodegen generate`.
# Never hand-edit Wait.xcodeproj/project.pbxproj; edit this file instead.
# Every module lives in the local package Packages/WaitKit; only the app, widget and watch app are Xcode targets.
name: Wait
options:
  bundleIdPrefix: com.chenkai
  deploymentTarget:
    iOS: "17.0"
    watchOS: "10.0"
  createIntermediateGroups: true
  developmentLanguage: en
configFiles:
  Debug: Config/Base.xcconfig
  Release: Config/Base.xcconfig
settings:
  base:
    DEVELOPMENT_TEAM: 5WDN96EM72
    CODE_SIGN_STYLE: Automatic
    SWIFT_VERSION: "5.0"
    MARKETING_VERSION: "1.0"
    CURRENT_PROJECT_VERSION: "1"
packages:
  WaitKit:
    path: Packages/WaitKit
  # Remote packages used only by the watch app until plan 03 rewrites it on top of WaitKit.
  Alamofire:
    url: https://github.com/Alamofire/Alamofire
    from: 5.4.3
  Money:
    url: https://github.com/Flight-School/Money
    from: 1.3.0
  SwiftyJSON:
    url: https://github.com/SwiftyJSON/SwiftyJSON
    from: 5.0.1
targets:
  Wait:
    type: application
    platform: iOS
    sources:
      - path: Wait
      - path: Shared/Connectivity.swift
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.chenkai.wait
        INFOPLIST_FILE: Wait/Info.plist
        TARGETED_DEVICE_FAMILY: "1"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        DEVELOPMENT_ASSET_PATHS: '"Wait/Preview Content"'
        ENABLE_PREVIEWS: YES
        ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES: YES
        SUPPORTED_PLATFORMS: iphoneos iphonesimulator
        SUPPORTS_MACCATALYST: NO
        SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO
      configs:
        Debug:
          CODE_SIGN_ENTITLEMENTS: Wait/Wait.entitlements
        Release:
          CODE_SIGN_ENTITLEMENTS: Wait/WaitRelease.entitlements
    dependencies:
      - package: WaitKit
        product: DesignSystem
      - package: WaitKit
        product: Logging
      - package: WaitKit
        product: Model
      - package: WaitKit
        product: CacheService
      - package: WaitKit
        product: Networking
      - package: WaitKit
        product: StockCharts
      - package: WaitKit
        product: LegacyStockDetails
      - package: WaitKit
        product: SettingsTab
      - target: WaitWidgetExtension
      - target: WaitWatch
        embed: true
        link: false
        codeSign: true
        copy:
          destination: productsDirectory
          subpath: "$(CONTENTS_FOLDER_PATH)/Watch"
  WaitWidgetExtension:
    type: app-extension
    platform: iOS
    sources:
      - path: WaitWidget
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.chenkai.wait.WaitWidget
        INFOPLIST_FILE: WaitWidget/Info.plist
        TARGETED_DEVICE_FAMILY: "1,2"
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME: WidgetBackground
        SKIP_INSTALL: YES
      configs:
        Release:
          CODE_SIGN_ENTITLEMENTS: WaitWidgetExtensionRelease.entitlements
    dependencies:
      - package: WaitKit
        product: DesignSystem
      - package: WaitKit
        product: Logging
      - package: WaitKit
        product: Model
      - package: WaitKit
        product: CacheService
      - package: WaitKit
        product: Networking
      - sdk: SwiftUI.framework
      - sdk: WidgetKit.framework
  WaitWatch:
    type: application
    platform: watchOS
    sources:
      - path: "WaitWatch Watch App"
      - path: Shared/Connectivity.swift
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.chenkai.wait.watchkitapp
        INFOPLIST_FILE: "WaitWatch Watch App/Info.plist"
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_CFBundleDisplayName: WaitWatch
        INFOPLIST_KEY_UISupportedInterfaceOrientations: UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown
        INFOPLIST_KEY_WKApplication: YES
        INFOPLIST_KEY_WKCompanionAppBundleIdentifier: com.chenkai.wait
        INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp: NO
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        DEVELOPMENT_ASSET_PATHS: '"WaitWatch Watch App/Preview Content"'
        ENABLE_PREVIEWS: YES
        SKIP_INSTALL: YES
        TARGETED_DEVICE_FAMILY: "4"
        LD_RUNPATH_SEARCH_PATHS: "$(inherited) @executable_path/Frameworks"
    dependencies:
      - package: Money
      - package: SwiftyJSON
      - package: Alamofire
schemes:
  Wait:
    build:
      targets:
        Wait: all
    run:
      config: Debug
    profile:
      config: Release
    analyze:
      config: Debug
    archive:
      config: Release
  WaitWatch:
    build:
      targets:
        WaitWatch: all
    run:
      config: Debug
    archive:
      config: Release
```
The `Wait` scheme no longer has a test action. All tests run through `WaitKit-Package` (command D). `bundleIdPrefix` changed to `com.chenkai`, but every target sets its bundle id explicitly, so this changes nothing.

- [ ] **Step 4: Regenerate and confirm the project has three targets**

```sh
cd /Users/ckai/code/Wait/Wait && xcodegen generate | tail -1 \
  && xcodebuild -list -project Wait.xcodeproj 2>/dev/null | sed -n '/Targets:/,/Build Configurations:/p' | sed '/^$/d'
```
Expected:
```
Created project at /Users/ckai/code/Wait/Wait/Wait.xcodeproj
    Targets:
        Wait
        WaitWidgetExtension
        WaitWatch
    Build Configurations:
```
The three target lines may appear in a different order. Then repeat the Package.resolved check from Task 2 Step 3.

- [ ] **Step 5: Build everything and run the package tests**

Run commands D, B and E. Expected, in that order: `Executed 4 tests, with 0 failures` with `** TEST SUCCEEDED **`, then `** BUILD SUCCEEDED **`, then `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Smoke-run the app on the seeded simulator**

Run as one block:
```sh
UDID=$(xcrun simctl list devices available | awk '/-- iOS 27.0 --/{f=1;next} /^--/{f=0} f && /iPhone 17 \(/{match($0,/[0-9A-F-]{36}/); print substr($0,RSTART,RLENGTH); exit}')
xcrun simctl boot "$UDID" 2>/dev/null || true
xcodebuild -project /Users/ckai/code/Wait/Wait/Wait.xcodeproj -scheme Wait -destination "id=$UDID" \
  -derivedDataPath /Users/ckai/code/Wait/build/DerivedData -skipMacroValidation -skipPackagePluginValidation build 2>&1 | tail -1
xcrun simctl install "$UDID" /Users/ckai/code/Wait/build/DerivedData/Build/Products/Debug-iphonesimulator/Wait.app
xcrun simctl launch "$UDID" com.chenkai.wait
sleep 5
xcrun simctl spawn "$UDID" launchctl list | grep -c "UIKitApplication:com.chenkai.wait"
xcrun simctl io "$UDID" screenshot /tmp/wait-plan01-task12.png
```
Expected:
- `** BUILD SUCCEEDED **`
- `com.chenkai.wait: <pid>`
- `1`, meaning the app is still running after 5 s and didn't crash
- `Wrote screenshot to: /tmp/wait-plan01-task12.png`

(manual: user, if Task 1 Step 7 seeded data) Open the screenshot or the simulator and confirm the watchlist shows the same stocks as before.

- [ ] **Step 7: Commit**

```sh
cd /Users/ckai/code/Wait && git add -A Wait && git status --short | grep -v '^[RMAD] ' ; git commit -m "$(cat <<'EOF'
refactor(waitkit): move StockDetailsFeature (as LegacyStockDetails) and SettingsTab; drop UI and vacuous tests

The Xcode project now has three targets: Wait, WaitWidgetExtension, WaitWatch.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Chunk 5: TCA 1.26 and docs

### Task 13: Upgrade TCA to 1.26.2 and port the two legacy reducers

TCA is now linked into one binary, the app, so its global `DependencyValues` exists once. The upgrade is safe from this point on (overview D2).

| Area | Old | New |
|---|---|---|
| Reducer | `Reducer<State, Action, Environment>` closure, `*ReducerBuilder`, `*Environment` | `@Reducer` structs `ChecklistListReducer` and `ChecklistEditReducer` with `@ObservableState` |
| Dependencies | `uuid` closure in an environment | `@Dependency(\.uuid)` |
| Storage | environment fields | injected through the reducer's `init` (constructor DI), so tests never touch disk |
| Views | `WithViewStore` | read the store directly (iOS 17 Observation) |
| Tests | XCTest | Swift Testing |

The reducer names avoid the module names `Checklist` and `ChecklistEditFeature`, because a type named like its module breaks qualified lookup. This port is deliberately minimal: plan 02 replaces both modules.

**Files:**
- Modify:
  - `Wait/Packages/WaitKit/Package.swift` (the TCA requirement)
  - `Wait/Packages/WaitKit/Sources/Checklist/ChecklistListTCA.swift`
  - `Wait/Packages/WaitKit/Sources/Checklist/ChecklistListView.swift`
  - `Wait/Packages/WaitKit/Sources/ChecklistEditFeature/ChecklistEditTCA.swift`
  - `Wait/Packages/WaitKit/Sources/ChecklistEditFeature/ChecklistEditView.swift`
  - `Wait/Packages/WaitKit/Sources/LegacyStockDetails/View/StockDetailsView.swift` (lines 254–260, the inline store)
  - `Wait/Wait.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- Test:
  - `Wait/Packages/WaitKit/Tests/ChecklistTests/ChecklistListTests.swift`
  - `Wait/Packages/WaitKit/Tests/ChecklistEditFeatureTests/ChecklistEditFeatureTests.swift`

- [ ] **Step 1: Confirm the latest TCA 1.x tag**

```sh
git ls-remote --tags https://github.com/pointfreeco/swift-composable-architecture | awk -F/ '{print $3}' | grep -E '^1\.[0-9]+\.[0-9]+$' | sort -V | tail -1
```
Expected: `1.26.2` or a later 1.x. The `from: "1.26.2"` requirement below accepts any later 1.x. Never move to a 2.x major in this plan.

- [ ] **Step 2: Write the failing tests: replace `Wait/Packages/WaitKit/Tests/ChecklistTests/ChecklistListTests.swift`**

```swift
//
// Created by: kai_chen on 12/28/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Foundation
import Model
import Testing
@testable import Checklist

// MARK: - ChecklistListTests

@MainActor
@Suite("ChecklistListReducer")
struct ChecklistListTests {
  // MARK: Internal

  @Test("checking then unchecking every item toggles isChecked")
  func checkAndUncheck() async {
    let store = TestStore(initialState: ChecklistListReducer.State(checklistItems: items)) {
      ChecklistListReducer(save: { _ in })
    }

    for index in items.indices {
      await store.send(.check(index: index)) {
        $0.checklistItems[index].isChecked = true
      }
      await store.send(.uncheck(index: index)) {
        $0.checklistItems[index].isChecked = false
      }
    }
  }

  @Test("every toggle persists the whole list")
  func persistsOnEveryToggle() async {
    let saved = LockIsolated<[[ChecklistItem]]>([])
    let store = TestStore(initialState: ChecklistListReducer.State(checklistItems: items)) {
      ChecklistListReducer(save: { items in saved.withValue { $0.append(items) } })
    }

    await store.send(.check(index: 1)) {
      $0.checklistItems[1].isChecked = true
    }

    #expect(saved.value.count == 1)
    #expect(saved.value.last?.map(\.isChecked) == [false, true])
  }

  // MARK: Private

  private let items = [
    ChecklistItem(name: "first", id: UUID(0)),
    ChecklistItem(name: "second", id: UUID(1)),
  ]
}
```

- [ ] **Step 3: Write the failing tests: replace `Wait/Packages/WaitKit/Tests/ChecklistEditFeatureTests/ChecklistEditFeatureTests.swift`**

Keep `MockChecklistDataManager.swift` unchanged.
```swift
//
// Created by: kai_chen on 12/23/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Foundation
import Model
import Testing
@testable import ChecklistEditFeature

// MARK: - ChecklistEditFeatureTests

@MainActor
@Suite("ChecklistEditReducer")
struct ChecklistEditFeatureTests {
  // MARK: Internal

  @Test("adding inserts an empty item at the top, then editing renames it")
  func addNewItem() async {
    let store = TestStore(initialState: ChecklistEditReducer.State(items: items)) {
      ChecklistEditReducer(dataManager: MockChecklistDataManager())
    } withDependencies: {
      $0.uuid = .constant(UUID(100))
    }

    await store.send(.addItem) {
      $0.items.insert(ChecklistItem(name: "", id: UUID(100)), at: 0)
    }
    await store.send(.itemDidChange(index: 0, text: "New")) {
      $0.items[0].name = "New"
    }
  }

  @Test("load replaces the items with the stored list")
  func loadItems() async {
    let store = TestStore(initialState: ChecklistEditReducer.State(items: [])) {
      ChecklistEditReducer(dataManager: MockChecklistDataManager(items: items))
    }

    await store.send(.load) {
      $0.items = items
    }
  }

  @Test("save hands the current items to the data manager")
  func saveItems() async {
    let dataManager = MockChecklistDataManager()
    let store = TestStore(initialState: ChecklistEditReducer.State(items: items)) {
      ChecklistEditReducer(dataManager: dataManager)
    }

    await store.send(.save)

    #expect(dataManager.items == items)
  }

  // MARK: Private

  private let items = [
    ChecklistItem(name: "First", id: UUID(0)),
    ChecklistItem(name: "Second", id: UUID(1)),
    ChecklistItem(name: "Third", id: UUID(2)),
  ]
}
```

- [ ] **Step 4: Run the tests and watch them fail**

Run command D with the full log saved:
```sh
cd /Users/ckai/code/Wait/Wait/Packages/WaitKit && xcodebuild test -scheme WaitKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation > /tmp/wait-task13-red.log 2>&1; \
  tail -1 /tmp/wait-task13-red.log; grep -E "Tests/(ChecklistTests|ChecklistEditFeatureTests)/[^:]+\.swift:[0-9]+:[0-9]+: error:" /tmp/wait-task13-red.log | head -8
```
Expected: `** TEST FAILED **`, plus compile errors located in the two test files. On 0.31, `ChecklistListReducer` and `ChecklistEditReducer` already exist as typealiases of the old `Reducer<State, Action, Environment>`, so the errors are **not** "cannot find …". Expect messages like these (exact wording varies with the compiler):
- `'State' is not a member type of …`
- `extra argument 'save' in call`, and `extra argument 'dataManager' in call`
- `no exact matches in call to initializer`, from the new `TestStore(initialState:) { … }` form and from `UUID(0)`
- `cannot find 'LockIsolated' in scope`

At least one error must come from each of the two test files.

- [ ] **Step 5: Upgrade TCA in `Wait/Packages/WaitKit/Package.swift`**

Replace these two lines:
```swift
    // Task 13 of plan 01 upgrades this to 1.26.2.
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", exact: "0.31.0"),
```
with:
```swift
    .package(
      url: "https://github.com/pointfreeco/swift-composable-architecture",
      from: "1.26.2",
      traits: ["ComposableArchitecture2Deprecations"]
    ),
```
Then resolve:
```sh
xcodebuild -resolvePackageDependencies -project /Users/ckai/code/Wait/Wait/Wait.xcodeproj -scheme Wait 2>&1 | grep -E "swift-composable-architecture|swift-dependencies|swift-sharing" 
```
Expected: lines showing `swift-composable-architecture: … @ 1.26.2` (or the later 1.x from Step 1), plus the new transitive `swift-dependencies` and `swift-sharing`.

- [ ] **Step 6: Port `ChecklistListTCA.swift` and its view**

Replace the whole of `Wait/Packages/WaitKit/Sources/Checklist/ChecklistListTCA.swift` with:
```swift
//
// Created by: kai_chen on 12/16/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Foundation
import Model

// MARK: - ChecklistListReducer

/// Checks and unchecks a stock's checklist and persists every change.
/// Persistence is injected (`save`) so tests never write to disk.
@Reducer
public struct ChecklistListReducer {
  // MARK: Lifecycle

  public init(save: @escaping ([ChecklistItem]) -> Void) {
    self.save = save
  }

  public init(storage: ChecklistStorage) {
    self.init(save: { storage.save(checklistItems: $0) })
  }

  // MARK: Public

  @ObservableState
  public struct State: Equatable {
    // MARK: Lifecycle

    public init(checklistItems: [ChecklistItem]) {
      self.checklistItems = checklistItems
    }

    // MARK: Public

    public var checklistItems: [ChecklistItem]
  }

  public enum Action: Equatable {
    case check(index: Int)
    case uncheck(index: Int)
  }

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
        case let .check(index):
          state.checklistItems[index].isChecked = true
        case let .uncheck(index):
          state.checklistItems[index].isChecked = false
      }
      save(state.checklistItems)
      return .none
    }
  }

  // MARK: Private

  private let save: ([ChecklistItem]) -> Void
}
```
Replace the whole of `Wait/Packages/WaitKit/Sources/Checklist/ChecklistListView.swift` with:
```swift
//
// Created by: kai_chen on 12/16/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Model
import SwiftUI

// MARK: - ChecklistListView

public struct ChecklistListView: View {
  // MARK: Lifecycle

  public init(store: StoreOf<ChecklistListReducer>) {
    self.store = store
  }

  // MARK: Public

  public var body: some View {
    List(store.checklistItems) { item in
      Checklist(item: item) { tapped in
        guard let index = store.checklistItems.firstIndex(of: tapped) else {
          return
        }
        store.send(tapped.isChecked ? .uncheck(index: index) : .check(index: index))
      }
    }
    .navigationTitle(navigationTitle(with: store.checklistItems))
  }

  // MARK: Private

  private let store: StoreOf<ChecklistListReducer>

  private func navigationTitle(with checklistItems: [ChecklistItem]) -> String {
    let itemCheckedCount = checklistItems.reduce(into: 0) { count, item in
      count += item.isChecked ? 1 : 0
    }

    if itemCheckedCount == checklistItems.count {
      return "All Done"
    } else {
      return "\(itemCheckedCount) / \(checklistItems.count)"
    }
  }
}

// MARK: - ChecklistListView_Previews

struct ChecklistListView_Previews: PreviewProvider {
  static var previews: some View {
    ChecklistListView(
      store: Store(
        initialState: ChecklistListReducer.State(checklistItems: [
          ChecklistItem(name: "First", id: UUID()),
          ChecklistItem(name: "Second", id: UUID()),
          ChecklistItem(name: "Third", id: UUID()),
        ])
      ) {
        ChecklistListReducer(save: { _ in })
      }
    )
  }
}
```

- [ ] **Step 7: Port `ChecklistEditTCA.swift` and its view, and the inline store in `StockDetailsView`**

Replace the whole of `Wait/Packages/WaitKit/Sources/ChecklistEditFeature/ChecklistEditTCA.swift` with:
```swift
//
// Created by: kai_chen on 10/9/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Foundation
import Model

// MARK: - ChecklistEditReducer

/// Edits the checklist template. The data manager is injected; ids come from `@Dependency(\.uuid)`.
@Reducer
public struct ChecklistEditReducer {
  // MARK: Lifecycle

  public init(dataManager: ChecklistDataManager) {
    self.dataManager = dataManager
  }

  // MARK: Public

  @ObservableState
  public struct State: Equatable {
    // MARK: Lifecycle

    public init(items: [ChecklistItem]) {
      self.items = items
    }

    // MARK: Public

    public var items: [ChecklistItem]
  }

  public enum Action: Equatable {
    case addItem
    case save
    case load
    case itemDidChange(index: Int, text: String)
  }

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
        case .addItem:
          state.items.insert(ChecklistItem(name: "", id: uuid()), at: 0)
          return .none
        case .load:
          if let checklistItems = dataManager.load() {
            state.items = checklistItems
          }
          return .none
        case .save:
          dataManager.save(items: state.items)
          return .none
        case let .itemDidChange(index, text):
          state.items[index].name = text
          return .none
      }
    }
  }

  // MARK: Private

  @Dependency(\.uuid) private var uuid

  private let dataManager: ChecklistDataManager
}
```
Replace the whole of `Wait/Packages/WaitKit/Sources/ChecklistEditFeature/ChecklistEditView.swift` with:
```swift
//
// Created by: kai_chen on 10/9/21.
// Copyright © 2021 Wait. All rights reserved.
//

import ComposableArchitecture
import Model
import SwiftUI

// MARK: - ChecklistEditView

public struct ChecklistEditView: View {
  // MARK: Lifecycle

  public init(store: StoreOf<ChecklistEditReducer>) {
    self.store = store
  }

  // MARK: Public

  public var body: some View {
    List {
      ForEach(Array(store.items.enumerated()), id: \.element.id) { index, _ in
        TextField(
          "New Item",
          text: Binding(
            get: { store.items[index].name },
            set: { store.send(.itemDidChange(index: index, text: $0)) }
          )
        )
      }
    }
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button("Save") {
          store.send(.save)
        }
        Button(action: { store.send(.addItem) }) {
          Image(systemName: "plus")
        }
      }
    }
    .onDisappear {
      store.send(.save)
    }
    .onAppear {
      store.send(.load)
    }
  }

  // MARK: Internal

  @Bindable var store: StoreOf<ChecklistEditReducer>
}

// MARK: - ChecklistEditView_Previews

struct ChecklistEditView_Previews: PreviewProvider {
  static var previews: some View {
    ChecklistEditView(
      store: Store(
        initialState: ChecklistEditReducer.State(items: [
          ChecklistItem(name: "First", id: UUID()),
          ChecklistItem(name: "Second", id: UUID()),
        ])
      ) {
        ChecklistEditReducer(dataManager: DefaultChecklistDataManager())
      }
    )
  }
}
```
In `Wait/Packages/WaitKit/Sources/LegacyStockDetails/View/StockDetailsView.swift`, replace lines 254–260:
```swift
        NavigationLink("Let's check") {
          ChecklistListView(store: Store<ChecklistListState, ChecklistListAction>.init(
            initialState: ChecklistListState(checklistItems: checklistItems),
            reducer: ChecklistListReducerBuilder.build(),
            environment: ChecklistListEnvironment(checklistStorage: checklistStorage)
          ))
        }
```
with:
```swift
        NavigationLink("Let's check") {
          ChecklistListView(store: Store(initialState: ChecklistListReducer.State(checklistItems: checklistItems)) {
            ChecklistListReducer(storage: checklistStorage)
          })
        }
```
Then confirm nothing still uses the 0.31 API:
```sh
cd /Users/ckai/code/Wait/Wait && grep -rnE "WithViewStore|ReducerBuilder|ChecklistListEnvironment|ChecklistEditEnvironment|ChecklistListState|ChecklistListAction|ChecklistEditState|ChecklistEditAction" --include='*.swift' Packages Wait WaitWidget
```
Expected: no output.

- [ ] **Step 8: Run the tests and watch them pass**

Run command D. Expected: `✔ Test run with 5 tests in 2 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 9: Build the app and the watch, then smoke-run**

Run commands B and E. Expected: `** BUILD SUCCEEDED **` twice. Then repeat the Task 12 Step 6 block, writing the screenshot to `/tmp/wait-plan01-task13.png`. Expected: the same four results.

(manual: user) On the simulator:
1. Open a stock, tap **Let's check**, check two items, go back, and reopen. The two items must still be checked.
2. The watchlist, expected prices and notes must match what was seeded in Task 1 Step 7.

- [ ] **Step 10: Commit**

```sh
cd /Users/ckai/code/Wait && git add -A Wait && git status --short | grep -v '^[RMAD] ' ; git commit -m "$(cat <<'EOF'
feat(tca): upgrade to TCA 1.26 and port the checklist reducers to @Reducer/@ObservableState

- ChecklistListReducer / ChecklistEditReducer with constructor-injected persistence
- @Dependency(\.uuid) replaces the environment closure
- Views drop WithViewStore; tests move to Swift Testing

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 14: Docs, the Bitrise checklist and the final verification

**Files:**
- Modify: `CLAUDE.md` (full rewrite below)
- Create: `Wait/Packages/WaitKit/README.md`

- [ ] **Step 1: Replace `CLAUDE.md` with the post-plan-01 version**

`AGENTS.md` is a symlink to this file and needs no change.
````markdown
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Wait ("Great Stock Takes Time") is a SwiftUI stock-alert app. The user keeps a watchlist with an *expected price* per stock, and the app shows whether the current price says **buy / almost / wait** (`Stock.tradeAction`, with a 5% "almost" band). The repo has an iOS app (iOS 17), a WidgetKit extension, and a watchOS 10 app. CI runs on Bitrise; its config lives in Bitrise, not in this repo.

The modernization plans live in `docs/superpowers/plans/`. Start with `2026-11-22-wait-00-overview.md`. Plan 01 (foundation) is done. Plan 02 replaces the legacy modules described below.

## Commands

The Xcode project is **generated by XcodeGen** from `Wait/project.yml`. `Wait/Wait.xcodeproj` is committed, so Xcode and CI don't need XcodeGen. **Never hand-edit `project.pbxproj`**: change `project.yml` and regenerate. After regenerating, check that `Wait/Wait.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` still exists.

Run `xcodebuild` and `xcodegen` outside any agent sandbox. SwiftPM's manifest sandbox can't nest, and it fails with `sandbox_apply: Operation not permitted`.

```sh
# Regenerate the Xcode project after editing Wait/project.yml
cd Wait && xcodegen generate

# Build the iOS app (also builds the widget, the embedded watch app and every WaitKit module)
xcodebuild -project Wait/Wait.xcodeproj -scheme Wait \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -skipMacroValidation -skipPackagePluginValidation build

# Build the watch app on its own
xcodebuild -project Wait/Wait.xcodeproj -scheme WaitWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 12 (42mm),OS=27.0' \
  -skipMacroValidation -skipPackagePluginValidation build

# Run all unit tests (they live in the WaitKit package)
cd Wait/Packages/WaitKit && xcodebuild test -scheme WaitKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation

# Run one Swift Testing test (the identifier ends in "()")
cd Wait/Packages/WaitKit && xcodebuild test -scheme WaitKit-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation \
  -only-testing:ChecklistEditFeatureTests/ChecklistEditFeatureTests/addNewItem\(\)

# Scan tracked files for hard-coded credentials (also a CI step)
scripts/check-secrets.sh

# Format and lint (configs live in Wait/, so run from there; neither runs as a build phase)
cd Wait && swiftformat .     # needs `brew install swiftformat`
cd Wait && swiftlint

# Dead-code scan (run by hand; the old "Unused Code" target is gone)
cd Wait && periphery scan --project Wait.xcodeproj --schemes Wait --targets Wait --format xcode
```

- `-skipMacroValidation` is required for TCA's macros on the command line.
- The shared schemes are `Wait` (app, widget and embedded watch app) and `WaitWatch`.
- Tests run through the package's auto-generated `WaitKit-Package` scheme. The `Wait` scheme has no test action.
- The test targets are `ChecklistTests` and `ChecklistEditFeatureTests`, both using Swift Testing.
- SPM dependencies are declared in two places:
  - `Wait/Packages/WaitKit/Package.swift`: TCA 1.26 and the legacy pins (Money 1.3.0, Alamofire 5.5.0, SwiftyJSON 5.0.1).
  - `Wait/project.yml`: Money, Alamofire and SwiftyJSON again, for the watch app only.

  They are pinned in `Wait/Wait.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

## Architecture

### Module graph

There are only three Xcode targets: `Wait` (the iOS app), `WaitWidgetExtension` and `WaitWatch` (sources in `Wait/WaitWatch Watch App/`). Every other module is a library target in the local package `Wait/Packages/WaitKit`, linked statically into the app (and the widget). Only `public` symbols are visible across modules.

The modules below are **legacy**: they were moved unchanged from the old framework targets, they compile in Swift 5 language mode, and plan 02 replaces them. Dependencies, from the actual imports:

```
DesignSystem (old Color + Size), Logging (os.Logger shim)     leaf targets
Model            -> DesignSystem, Money                         Stock, StockCurrentQuote, StockQuote, StockOverview, ChecklistItem, TradeAction…
Networking       -> Model, Logging                              NetworkingURLBuilder + URLDomain, StockCurrentQuoteNetworkClient
CacheService     -> Model, Logging                              Storage<T: Codable> (JSON file), Cache<K,V> (NSCache), StockCache.shared
StockCharts      -> CacheService, Networking, Model, DesignSystem, Logging, Money, Alamofire, SwiftyJSON
Checklist        -> CacheService, DesignSystem, Model, Logging, TCA       per-stock checklist (ChecklistListReducer)
ChecklistEditFeature -> Logging, Model, TCA                     checklist template editor (ChecklistEditReducer); only used in previews so far
LegacyStockDetails   -> StockCharts, Checklist, CacheService, Networking, Model, DesignSystem, Logging, Money, TCA   the stock detail screen
SettingsTab      -> ChecklistEditFeature, Model, TCA            placeholder view
Wait (app)       -> DesignSystem, Logging, Model, Networking, CacheService, StockCharts, LegacyStockDetails, SettingsTab; owns the Waitlist screens (Wait/Wait/Waitlist)
WaitWidget       -> DesignSystem, Logging, Model, Networking, CacheService
```

### Data flow

- **Watchlist source of truth:** `CacheService.StockCache.shared` holds `[Stock]` in memory and persists it through `Storage` to `Documents/stocks`. `Waitlist/DataSource/StockCurrentQuoteDataSource` loads from it, then refreshes every quote in one batch call. `StockDetailsView` writes edits back with `StockCache.shared.saveStock`.
- **APIs:** `NetworkingURLBuilder.buildURL(domain:api:params:)` adds the Twelve Data key as a query item. The key comes from the Info.plist key `TwelveDataAPIKey`, which is filled from the build setting `TWELVE_DATA_API_KEY`, which is defined in the gitignored `Wait/Config/Secrets.xcconfig` (template: `Secrets.example.xcconfig`).
  - Twelve Data endpoints: `quote`, `symbol_search` and `time_series`.
  - Alpha Vantage `OVERVIEW` is Premium-only, so `EmptyStockOverviewNetworkClient` returns `StockOverview.empty` until plan 04.
  - A batch `quote` call with one symbol returns a different JSON shape. `StockCurrentQuoteNetworkClient.fetchDetails(stocks:)` handles that case separately.
- **On-disk caches:** all are `Storage` JSON files in Documents:
  - chart history: `cache-price-history-<SYMBOL>`
  - per-stock checklists: `checklist-<SYMBOL>`
  - the checklist template: `checklist-items.json`
- **`Stock` is immutable.** Derive copies with `with(currentQuote:)` or `with(memo:)`. `==` and `hash` ignore `currentQuote`, and hashing uses only `symbol`. Prices are `Money<USD>`.

### Two presentation patterns coexist

1. **Most screens:** a SwiftUI view with an `ObservableObject` `*DataSource`, which calls a `*NetworkClient` that returns a Combine `AnyPublisher`. `PriceHistoryNetworkClient` uses Alamofire + SwiftyJSON instead.
2. **Checklist features:** TCA **1.26**. They use `@Reducer` structs (`ChecklistListReducer`, `ChecklistEditReducer`) with `@ObservableState`.
   - Persistence is injected through the reducer's `init`, and ids come from `@Dependency(\.uuid)`.
   - Views read the store directly (iOS 17 Observation), with no `WithViewStore`.
   - Tests use `TestStore(initialState:) { Reducer(...) } withDependencies: { … }` under Swift Testing.

### watchOS app and connectivity

- The `WaitWatch` target (sources in `Wait/WaitWatch Watch App/`, bundle id `com.chenkai.wait.watchkitapp`, companion `com.chenkai.wait`) is embedded in the iOS app's `Watch/` folder. A watch compile error therefore breaks the app build.
- It still compiles its own **copies** of `Stock`, `StockCurrentQuote`, `TradeAction`, `TimeSection`, `Size` and `PriceHistory*`. These have drifted from the originals, and plan 03 replaces them with WaitKit's shared `Domain`.
- Its `StockCurrentQuoteDataSource.fetchStocks()` still uses a hard-coded stock list.
- `Shared/Connectivity.swift` is compiled into both apps and wraps `WCSession`. iOS `MainView` sends the watchlist symbols on appear, but the watch UI doesn't read `Connectivity.stockSymbols` yet.

### Widget caveat

`WaitWidget` calls `StockCache.shared`, but `Storage` writes to the current process's own Documents directory, not the app-group container. `group.chenkai.wait.contents` is declared only in the Release entitlements. So the widget doesn't see the app's saved stocks. Plan 02 fixes this.

### Third-party setup and credentials

- Logging: `Logger.shared.verbose/error` (the `Logging` module) forwards to `os.Logger` (subsystem `com.chenkai.wait`, category `legacy`). Shake and SwiftyBeaver were removed.
- No credentials live in source. `scripts/check-secrets.sh` fails on anything that looks like a hard-coded key. Put build-time secrets in `Wait/Config/Secrets.xcconfig` and expose them through Info.plist.

## Code style

The tools enforce this style through `Wait/.swiftformat` and `Wait/.swiftlint.yml`:

- 2-space indent. `case` is indented inside `switch`. No explicit `self`. Implicit returns. Line length is 180.
- SwiftFormat's `organizeDeclarations` and `markTypes` rules are on:
  - Each type is preceded by `// MARK: - TypeName`.
  - Members are grouped under `// MARK: Lifecycle`, `// MARK: Public`, `// MARK: Internal` and `// MARK: Private`, in that order.
  - Protocol conformances go in extensions marked `// MARK: ProtocolName`.
- File header, from `IDETemplateMacros.plist`:
  ```
  //
  // Created by: <name> on <date>.
  // Copyright © 2021 Wait. All rights reserved.
  //
  ```
````

- [ ] **Step 2: Write `Wait/Packages/WaitKit/README.md`**

````markdown
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
````

- [ ] **Step 3: Run the full definition-of-done check (overview §4.1, plan 01)**

Run commands D, B and E, then:
```sh
/Users/ckai/code/Wait/scripts/check-secrets.sh; echo "exit=$?"
cd /Users/ckai/code/Wait && git grep -nE 'apikey", value: "|apikey=|clientId:|clientSecret:' -- . ':!docs' ':!scripts/check-secrets.sh'; echo "grep-exit=$?"
cd /Users/ckai/code/Wait && grep -nE "Shake|SwiftyBeaver|SnapshotTesting|exact: \"0\.31" Wait/project.yml Wait/Packages/WaitKit/Package.swift; echo "deps-exit=$?"
cd /Users/ckai/code/Wait/Wait && xcodebuild -list -project Wait.xcodeproj 2>/dev/null | sed -n '/Targets:/,/Build Configurations:/p' | grep -c "^        "
```
Expected:
- D: `✔ Test run with 5 tests in 2 suites passed` and `** TEST SUCCEEDED **`
- B and E: `** BUILD SUCCEEDED **` each
- `check-secrets: OK` and `exit=0`
- no matches and `grep-exit=1`
- no matches and `deps-exit=1`
- `3` (the three targets)

- [ ] **Step 4 (manual: user): Update Bitrise**

The CI config lives in Bitrise, not this repo. In the Bitrise workflow editor for Wait:
1. **Stack:** choose an Xcode 27 stack (anything ≥ 16.3 works for TCA 1.26, but 27 matches local).
2. **Secrets:** add the secret env var `TWELVE_DATA_API_KEY`. Then add a Script step before building:
   `echo "TWELVE_DATA_API_KEY = $TWELVE_DATA_API_KEY" > Wait/Config/Secrets.xcconfig`
3. **Build step:** add the flags `-skipMacroValidation -skipPackagePluginValidation`, and use a destination the stack has (`iPhone 17` / its default iOS runtime).
4. **Schemes:** remove any reference to the deleted `Color` scheme.
5. **Tests:** replace the test step with a Script step:
   `cd Wait/Packages/WaitKit && xcodebuild test -scheme WaitKit-Package -destination 'platform=iOS Simulator,name=iPhone 17' -skipMacroValidation -skipPackagePluginValidation`
6. **Secret scan:** add a Script step running `scripts/check-secrets.sh`.
7. **APM:** remove the Bitrise APM step or its config, because `bitrise_configuration.plist` was deleted.

The executor prints this list for the user and continues. It doesn't block the commit.

- [ ] **Step 5: Commit**

```sh
cd /Users/ckai/code/Wait && git add CLAUDE.md Wait/Packages/WaitKit/README.md && git commit -m "$(cat <<'EOF'
docs: describe the XcodeGen + WaitKit foundation in CLAUDE.md and the package README

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Finish the branch**

Use superpowers:finishing-a-development-branch to verify, then offer to merge into or open a PR against `ck/new-version`, never `master`. The next plan is `2026-11-22-wait-02-ios-ladder-and-features.md`.
