# M4 Settings + Translation Providers

M4 connects the settings shell to durable app preferences and optional
bring-your-own-key cloud providers while keeping Apple Translation as the
private default path.

## Defaults

- Source language: Auto Detect.
- Target language: English.
- Engine: Apple Translation.
- Auto-copy: off.
- Launch at login: off.
- App language: System.
- Cmd+C+C and drag translation: off until explicitly enabled.
- Popup font size: 15 pt.
- Popup width: 420 px.
- Popup width follows selection: on.

Invalid persisted target languages fall back to English. Popup size values are
clamped to the Settings UI ranges during load.

## Providers

- Apple Translation uses the system on-device translation APIs and does not
  require a key.
- DeepL, Google Cloud Translation, and Microsoft Azure Translator are exposed
  as optional cloud engines.
- DeepL is not offered for translation requests where the selected or resolved
  source/target language is Thai, because DeepL does not support Thai.
- Microsoft Azure Translator accepts an optional region value for regional and
  multi-service Azure resources.
- Cloud engines can be selected in Settings, but translation fails with a
  missing-key error until a key for that provider is stored.
- Unit tests use mocked network clients. No test calls a provider endpoint.

The app sends text to a cloud provider only when that provider is selected for
the translation request. Apple Translation remains the default engine.

## API Keys

Provider keys and Azure region metadata are stored through the app's
`APIKeyStoring` abstraction. The live implementation stores each value as a
Keychain generic password under the LinguistMac service namespace.

Settings can save, test presence, and clear provider credentials. The test
action is a local readiness check; it does not send sample text to the provider.

## Launch At Login

Launch-at-login status is read from `SMAppService.mainApp`. Toggling the setting
registers or unregisters the main app service and persists the resulting setting
state.

## Privacy Notes

- API keys are not stored in UserDefaults.
- API key values are not displayed after saving.
- Provider errors should not include raw key values.
- The cloud provider UI describes the selected-provider data flow instead of
  implying that all translation text always leaves the device.
