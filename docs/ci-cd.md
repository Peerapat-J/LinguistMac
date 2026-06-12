# CI/CD

LinguistMac uses GitHub Actions to keep the clean-room macOS rewrite buildable as each feature lands.

## Continuous integration

The `CI` workflow runs on pull requests, pushes to `main`, and manual dispatches. It checks:

- SwiftLint in strict mode
- SwiftLint analyzer rules with compiler-log input
- SwiftFormat in lint mode
- `xcodebuild` build for `LinguistMac.xcodeproj` in Debug and Release
- `xcodebuild` unit tests for the shared `LinguistMac` scheme in Debug and Release
- strict Swift compiler checks with warnings treated as errors
- Xcode static analyzer checks with warnings treated as errors

## Delivery artifact

The workflow also builds an ad-hoc-signed `.app` artifact on pushes to `main`
and manual dispatches so development packages keep the sandbox entitlement. This
is only a development artifact, not a Developer ID signed or notarized release.

Use `./script/package_release.sh unsigned` for a reproducible local or CI dry
run that creates zip and DMG artifacts under `dist/release/`.

The `Release Artifact` workflow can also be run manually. `unsigned` mode works
without credentials. `signed` mode requires Developer ID and App Store Connect
notarization secrets described in `docs/release-checklist.md`.

Signed distribution should wait until the app identity, entitlements, Developer
ID signing, and notarization credentials are configured.

## Local parity

Run the same checks locally before pushing:

```sh
swiftlint lint --strict --no-cache
xcodebuild -project LinguistMac.xcodeproj -scheme LinguistMac -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/linguistmac-swiftlint CODE_SIGNING_ALLOWED=NO clean build > /tmp/linguistmac-swiftlint-analyze.log 2>&1
swiftlint analyze --strict --compiler-log-path /tmp/linguistmac-swiftlint-analyze.log
swiftformat --lint . --config .swiftformat --cache ignore
xcodebuild -project LinguistMac.xcodeproj -scheme LinguistMac -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/linguistmac-debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project LinguistMac.xcodeproj -scheme LinguistMac -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/linguistmac-release CODE_SIGNING_ALLOWED=NO build
xcodebuild -project LinguistMac.xcodeproj -scheme LinguistMac -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/linguistmac-debug-test CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES test
xcodebuild -project LinguistMac.xcodeproj -scheme LinguistMac -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/linguistmac-release-test CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES test
xcodebuild -project LinguistMac.xcodeproj -scheme LinguistMac -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/linguistmac-strict CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES build
xcodebuild -project LinguistMac.xcodeproj -scheme LinguistMac -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/linguistmac-analyze CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES CLANG_ANALYZER_NONNULL=YES analyze
./script/build_and_run.sh --package
./script/package_release.sh unsigned
codesign -d --entitlements :- dist/LinguistMac.app
```
