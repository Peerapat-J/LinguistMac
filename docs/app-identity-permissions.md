# App Identity And Permission Baseline

This document records the M0 identity and permission posture for LinguistMac.
It should be updated whenever app capabilities or distribution choices change.

## App Identity

- Display name: `LinguistMac`
- Bundle identifier: `com.peerapatj.LinguistMac`
- Minimum macOS: `15.0`
- Initial short version: `0.1`
- Initial build version: `1`
- Category: `public.app-category.utilities`

`LinguistMac.xcodeproj` uses `Configuration/LinguistMac/Info.plist` as the app
target Info.plist. The same values are mirrored in `AppIdentity.linguistMac` so
tests can catch accidental drift.

## Entitlement Baseline

`Configuration/LinguistMac/LinguistMac.entitlements` currently enables the App
Sandbox and outbound client networking for opt-in M4 cloud providers:

- `com.apple.security.app-sandbox`
- `com.apple.security.network.client`

The voice permission preparation slice adds microphone and speech-recognition
usage-description copy to `Configuration/LinguistMac/Info.plist`, but it does
not enable the sandbox audio-input entitlement or live capture. Add
`com.apple.security.device.audio-input` only in the runtime capture issue that
needs it.

Do not add file, automation, audio-input, or broader security exceptions until
the feature issue that requires them is implemented and reviewed.

## Permission Matrix

| Permission or capability | Needed for | M0 posture |
| --- | --- | --- |
| Screen Recording | Selected-region screenshot capture for OCR | Required for default screen translation; model and docs only in M0 |
| Accessibility | Selected text, double-copy, and drag translation workflows | Optional until M3 input modes |
| Microphone | Explicit push-to-talk voice capture | Modeled for M6 voice setup; no live capture or audio-input entitlement yet |
| Speech Recognition | Converting short spoken phrases into translatable text | Modeled for M6 voice setup; no runtime recognition flow yet |
| Keychain | Optional cloud provider API keys | Optional until M4 provider/key issues |
| Network client | Optional cloud translation providers | Enabled in M4 for user-selected BYOK providers only |
| Launch at login | User preference for startup behavior | Implemented in M4 app-preferences issue |

## Privacy Defaults

- Apple Translation remains the planned default provider.
- Auto-copy is off by default.
- Cloud translation providers are opt-in and require user-supplied keys.
- Network requests are made only by the selected cloud provider engine.
- No telemetry or auto-update integration is part of M0.
- Permission failures should become user-visible states rather than silent
  failures when feature workflows land.

## Review Checklist

- Does a feature require a new entitlement?
- Does it read selected text, clipboard text, captured screen content, or API
  keys?
- Does it send text over the network?
- Does the app still work when the permission is denied?
- Is the permission documented in this file and tested in core state models?
