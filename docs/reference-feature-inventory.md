# Reference Feature Inventory

This inventory captures high-level behavior for clean-room planning. It is based
on public README and CHANGELOG level information from `Peerapat-J/translateOnScreen`
as inspected on 2026-06-04. It must not be treated as implementation guidance.

## Product Shape

- macOS menu bar screen translation app.
- Personal-use fork, not a public download or auto-updating distribution.
- On-device default behavior through Apple Vision and Apple Translation.
- Optional bring-your-own-key cloud translation providers.
- No telemetry or Sparkle auto-update feed in the referenced fork target per
  its README.

## Capture And Input Modes

- Region-based screen selection for screen translation.
- Screen capture overlay with immediate selection affordance.
- Guard against re-triggering the overlay while already active.
- Selected text translation from other apps without OCR.
- Double-copy clipboard translation trigger.
- Drag translation behavior that requires Accessibility readiness.
- Quick Translate panel for typed text.

## OCR

- Apple Vision OCR.
- Text cleanup for natural sentence flow.
- Paragraph break preservation.
- Bullet and numbered list preservation where appropriate.
- User-visible no-text or OCR-failure states.

## Translation

- Apple Translation as the on-device default engine.
- Source language selection.
- Target language selection.
- Source auto-detect.
- Language swap.
- Language pack status and download guidance.
- Optional DeepL, Google Cloud Translation, and Microsoft Azure Translator
  providers when the user selects an engine and supplies a key.

## UI Surfaces

- Menu bar app shell.
- Settings window.
- Translation popup with translated text, original text toggle, copy, and close.
- Quick Translate floating panel.
- First-launch onboarding or setup guidance.
- History window or list.
- About/status surface.

## Settings

- Screen translation shortcut.
- Text selection shortcut.
- Quick Translate shortcut.
- Source and target language preferences.
- Engine selection.
- API key status for cloud providers.
- Auto-copy toggle.
- Launch at login toggle.
- Popup width behavior.
- Popup font size.
- Popup font family strategy.
- App language setting.

## Persistence

- Translation history.
- Recent translations in the menu bar.
- User-friendly timestamps.
- Automatic history trimming, currently planned as latest 50 records unless a
  later product decision changes it.
- Popup size or position preferences where useful.

## Permissions And Privacy

- Screen Recording is relevant to capture workflows.
- Accessibility is relevant to selected text, double-copy, and drag workflows.
- Clipboard paths must preserve user clipboard state unless the user explicitly
  enables auto-copy behavior.
- Cloud providers send text to the selected provider only when the user chooses
  that provider and configures a key.
- API keys must be stored securely and redacted from logs, tests, and errors.

## Release And Packaging

- Development artifacts can remain unsigned.
- Signed distribution, notarization, and packaging are release-readiness work.
- Auto-update and telemetry are out of the initial clean-room parity baseline
  unless explicitly approved in a future issue.

## Needs Confirmation

- Final default keyboard shortcuts.
- Final supported language catalog.
- Exact drag translation behavior.
- Whether app language should remain English/Korean only or expand later.
- Which fonts can be bundled or selected without licensing risk.
