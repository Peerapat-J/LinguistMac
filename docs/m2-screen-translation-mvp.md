# M2 Screen Translation MVP

## Scope

M2 wires the default on-device screen translation path:

1. Menu bar Screen Translate command opens a selected-region overlay.
2. The selected region is captured with ScreenCaptureKit.
3. Apple Vision OCR recognizes and normalizes source text.
4. The translation coordinator sends the text through the selected provider.
5. The popup presents loading, translated text, original text, copy, and failure states.

This milestone intentionally does not add global shortcut registration, durable history, cloud provider credential setup, selected-text translation, or drag/double-copy flows.

## Runtime Notes

- Selected-region capture uses `SCScreenshotManager.captureImage(in:)`, so the live capture path requires macOS 15.2 or newer.
- The Apple Translation provider is available only when the system supports `TranslationSession(installedSource:target:)`; older macOS versions surface a provider-unavailable state instead of falling back to cloud translation.

## Manual Smoke Test

Run the app package build first:

```sh
./script/build_and_run.sh --package
```

Then launch the app and verify:

1. Open the menu bar item and choose `Screen Translate`.
2. Select a visible region that contains text.
3. Confirm the translation popup moves from loading to a translated result.
4. Use `Show Original` and confirm the OCR source text is visible.
5. Use `Copy` and paste into a text field to confirm the translated text was copied.
6. Trigger `Screen Translate` again and press Escape to confirm cancellation shows a failure state without hanging the app.
7. Select an image/blank region and confirm the no-text path surfaces an error.
8. In Settings, change source/target languages and confirm Quick Translate uses the same language model and swap rules.

## Automated Validation

```sh
xcodebuild -project LinguistMac.xcodeproj -scheme LinguistMac -destination 'platform=macOS' test
git diff --check
```

The automated test suite covers coordinator state transitions, permission/no-text/language-pack failures, language selection/swap behavior, OCR text preprocessing, and duplicate capture-selection state handling.
