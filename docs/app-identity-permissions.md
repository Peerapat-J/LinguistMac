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

The SwiftPM packaging helper copies `Configuration/LinguistMac/Info.plist`
into the generated `.app` bundle. The same values are mirrored in
`AppIdentity.linguistMac` so tests can catch accidental drift.

## Entitlement Baseline

`Configuration/LinguistMac/LinguistMac.entitlements` currently enables only the
App Sandbox:

- `com.apple.security.app-sandbox`

Do not add network, file, automation, or broader security exceptions until the
feature issue that requires them is implemented and reviewed.

## Permission Matrix

| Permission or capability | Needed for | M0 posture |
| --- | --- | --- |
| Screen Recording | Selected-region screenshot capture for OCR | Required for default screen translation; model and docs only in M0 |
| Accessibility | Selected text, double-copy, and drag translation workflows | Optional until M3 input modes |
| Keychain | Optional cloud provider API keys | Optional until M4 provider/key issues |
| Network client | Optional cloud translation providers | Not enabled in baseline entitlement; add only with M4 provider work |
| Launch at login | User preference for startup behavior | Optional until M4 app-preferences issue |

## Privacy Defaults

- Apple Translation remains the planned default provider.
- Auto-copy is off by default.
- Cloud translation providers are opt-in and require user-supplied keys.
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
