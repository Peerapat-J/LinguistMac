# CI/CD

LinguistMac uses GitHub Actions to keep the clean-room macOS rewrite buildable as each feature lands.

## Continuous integration

The `CI` workflow runs on pull requests, pushes to `main`, and manual dispatches. It checks:

- `swift build --product LinguistMac`
- `swift test`
- `xcodebuild` build for the `LinguistMac` scheme
- `xcodebuild` test for the `LinguistMac-Package` scheme

## Delivery artifact

The workflow also builds an unsigned `.app` artifact on pushes to `main` and manual dispatches. This is only a development artifact, not a signed or notarized release.

Signed distribution should wait until the app identity, entitlements, Developer ID signing, and notarization flow are defined.

## Local parity

Run the same checks locally before pushing:

```sh
swift build --product LinguistMac
swift test
xcodebuild -scheme LinguistMac -destination 'platform=macOS' -derivedDataPath /tmp/linguistmac-derived CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme LinguistMac-Package -destination 'platform=macOS' -derivedDataPath /tmp/linguistmac-derived-test CODE_SIGNING_ALLOWED=NO test
./script/build_and_run.sh --package
```
