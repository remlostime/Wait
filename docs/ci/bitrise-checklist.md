# Bitrise update checklist

The Bitrise workflow lives in the Bitrise dashboard, not in this repo. After plans 01–03 the old workflow can no longer build. Apply every item, then trigger a build on the branch.

- [ ] **Stack:** choose an Xcode stack ≥ 16.3 (TCA 1.26 needs swift-tools 6.1). Xcode 27 is preferred, to match local development.
- [ ] **Flags:** add `-skipMacroValidation -skipPackagePluginValidation` to every `xcodebuild` invocation (Xcode Archive, Xcode Test, Script steps).
- [ ] **Destinations:** use the stack's simulators, e.g. `platform=iOS Simulator,name=iPhone 17,OS=27.0` and `platform=watchOS Simulator,name=Apple Watch Series 12 (42mm),OS=27.0`. The old `iPhone 15` destination is gone.
- [ ] **Schemes:**
  - Build the `Wait` scheme of `Wait/Wait.xcodeproj`.
  - Remove every step that uses the deleted `Color` scheme or the deleted "Unused Code" (periphery) target.
- [ ] **Tests:** replace the old test step with a Script step:
  ```sh
  cd Wait/Packages/WaitKit && xcodebuild test -scheme WaitKit-Package \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -skipMacroValidation -skipPackagePluginValidation
  ```
- [ ] **Watch:** optionally add a Script step that builds the `WaitWatch` scheme. The `Wait` build already compiles the watch app, because the app embeds it.
- [ ] **Secrets:**
  - Add a Script step **before** the build that writes the gitignored xcconfig from Bitrise Secrets:
    ```sh
    printf 'TWELVE_DATA_API_KEY = %s\n' "$TWELVE_DATA_API_KEY" > Wait/Config/Secrets.xcconfig
    ```
    After plan 04, write `WAIT_API_BASE_URL = https:/$()/<host>` instead.
  - Store the value as a Bitrise Secret, never in `bitrise.yml`.
- [ ] **Secret scan:** add a Script step `./scripts/check-secrets.sh`, and fail the build when it exits non-zero.
- [ ] **XcodeGen:** nothing is needed in CI, because the generated project is committed. Optionally add `brew install xcodegen && cd Wait && xcodegen generate && git diff --exit-code Wait.xcodeproj` to catch a stale project.
- [ ] **Server (after plan 04):** add a Script step `test -d server && (cd server && npm ci && npm run typecheck && npm test)`, using a Node 22 step or stack.
- [ ] **Bitrise APM:** if the workflow still references the Bitrise APM token plist that plan 01 removed, delete that step, and rotate the token in Bitrise.
