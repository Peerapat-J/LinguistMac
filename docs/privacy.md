# Privacy

LinguistMac defaults to on-device translation. Screen capture, OCR, language
selection, popup display, recent history, and local settings are handled on the
Mac unless the user explicitly selects and configures a cloud provider.

## Data Flow

- Screen Translate captures the selected screen region, runs Vision OCR locally,
  then sends recognized text to the selected translation provider.
- Selected Text, Cmd+C+C, Drag Translation, and Quick Translate send only the
  source text for the requested translation workflow.
- Voice translation permission setup is present, but live microphone capture is
  not enabled yet. Future push-to-talk voice capture should keep raw audio in
  memory only long enough to produce a transcript.
- Apple Translation uses Apple system frameworks and on-device language packs
  when available.
- Cloud providers send source text to the selected provider only after the user
  configures that provider's API key.
- API keys are stored in the macOS Keychain. The app does not print or persist
  keys in logs, settings, history, or release artifacts.
- Translation history is stored locally and trimmed to the latest 50 successful
  translations. Failed and cancelled attempts are not intentionally saved.

## Not Included In Initial Parity

- No telemetry or analytics dependency is included.
- No Sparkle feed or auto-update channel is included.
- No live voice capture, background listening, wake-word detection, or speech
  recognition runtime flow is included.
- No copied upstream website, privacy, email, update, or distribution links are
  included.
- No bundled font is included until licensing is reviewed and the asset is
  source-controlled.

## Privacy-Sensitive PR Checklist

- Does this change send text, screenshots, API keys, settings, or history to a
  new destination?
- Does the default path remain on-device unless a provider is explicitly
  selected and configured?
- Are user-facing errors redacted so source text and API keys are not shown in
  provider failure messages?
- Are logs free of source text, translated text, screenshots, and credentials?
- Are new permissions documented in `docs/app-identity-permissions.md` and the
  onboarding/settings surfaces?
