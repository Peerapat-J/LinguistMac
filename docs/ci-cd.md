# CI/CD

LinguistMac uses GitHub Actions to keep the clean-room macOS rewrite buildable as each feature lands.

## Continuous integration

The `CI` workflow runs on pull requests, pushes to `main`, and manual dispatches. It checks:

- SwiftLint in strict mode
- SwiftLint analyzer rules with compiler-log input
- SwiftFormat in lint mode
- `swift build` for Debug and Release
- `swift test` for Debug and Release
- `xcodebuild` build for the `LinguistMac` scheme in Debug and Release
- `xcodebuild` test for the `LinguistMac-Package` scheme in Debug and Release
- strict Swift compiler checks with warnings treated as errors
- Xcode static analyzer checks with warnings treated as errors

## Delivery artifact

The workflow also builds an unsigned `.app` artifact on pushes to `main` and manual dispatches. This is only a development artifact, not a signed or notarized release.

Signed distribution should wait until the app identity, entitlements, Developer ID signing, and notarization flow are defined.

## Local parity

Run the same checks locally before pushing:

```sh
swiftlint lint --strict --no-cache
xcodebuild -scheme LinguistMac -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/linguistmac-swiftlint CODE_SIGNING_ALLOWED=NO clean build > /tmp/linguistmac-swiftlint-analyze.log 2>&1
swiftlint analyze --strict --compiler-log-path /tmp/linguistmac-swiftlint-analyze.log
swiftformat --lint . --config .swiftformat --cache ignore
swift build -c debug --product LinguistMac
swift build -c release --product LinguistMac
swift test -c debug
swift test -c release
xcodebuild -scheme LinguistMac -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/linguistmac-debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme LinguistMac -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/linguistmac-release CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme LinguistMac-Package -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/linguistmac-debug-test CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES test
xcodebuild -scheme LinguistMac-Package -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/linguistmac-release-test CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES test
swift build -c debug --product LinguistMac -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete
xcodebuild -scheme LinguistMac -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/linguistmac-analyze CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES CLANG_ANALYZER_NONNULL=YES analyze
./script/build_and_run.sh --package
```
