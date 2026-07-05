# M6 Voice Translation Plan

This document scopes post-parity speech and voice translation work for issue
`#33`. It is a planning gate before any microphone, speech recognition, spoken
output, or live interpretation implementation starts.

## Product Goal

Let users translate spoken language without weakening the app's local-first
privacy posture or delaying text and screen translation parity. Voice work
should feel like an additional input and output workflow, not a replacement for
the existing translation flows.

The first useful version should help a user press a control, speak a short
phrase, review the transcript, and translate it through the same provider
routing used by the rest of the app.

## Voice Definition

Voice translation can mean several different behaviors. They should not ship as
one large feature.

| Behavior | Decision | Reason |
| --- | --- | --- |
| Speech-to-text input | First implementation candidate | Clear user value and can reuse existing translation providers after transcript capture |
| Spoken translated output | Later follow-up | Useful, but independent from microphone capture and can use system speech output |
| Live interpretation | Out of first pass | Requires streaming state, turn-taking UX, cancellation, latency handling, and stronger privacy review |
| Audio-file translation | Out of first pass | Adds file access, media duration limits, storage, and separate import UX |

The recommended first implementation is push-to-talk speech-to-text input for a
short phrase, followed by normal text translation. Spoken output can follow once
the transcript flow is stable.

## Candidate Surfaces

- Quick Translate: preferred first surface because the user already expects a
  direct text-entry workflow.
- Translation popup: eligible for showing the transcript and translated result,
  with the transcript treated like original text.
- Menu bar: can expose a Voice Translate command after permissions and settings
  are clear.
- Settings and onboarding: must explain microphone and speech-recognition
  permissions before runtime prompts appear.

Screen Translate, selected text, double-copy, and drag translation should not
change behavior for the first voice slice.

## First-Pass Requirements

- Capture one short spoken phrase through an explicit push-to-talk action.
- Show the recognized transcript before or alongside the translated text.
- Translate the transcript through the selected translation provider.
- Let the user cancel capture without saving a failed or partial translation.
- Handle denied microphone or speech-recognition permission with a recoverable
  user-facing state.
- Avoid saving raw audio, partial recognition hypotheses, provider diagnostics,
  or permission failure details in history.

## Framework And Provider Decision

The implementation must choose the capture and output path before code starts:

| Option | Benefit | Risk or cost |
| --- | --- | --- |
| Apple Speech framework for recognition | Fits the local-first posture when on-device recognition is available | Language availability and permission behavior need validation |
| AVFoundation microphone capture | Standard macOS capture path | Requires microphone usage description and sandbox audio-input review |
| Existing translation providers for transcripts | Reuses current provider routing and settings | Cloud providers receive recognized text when selected |
| System speech output | Avoids a new provider for spoken output | Voice availability and pronunciation quality vary by language |
| External speech or voice API | Richer recognition or speech synthesis | Adds a new data processor, credentials, network flow, cost, and privacy disclosure |

The first implementation should prefer Apple system frameworks for microphone
capture and speech recognition. External speech APIs should require a separate
issue because they change provider configuration, privacy review, and release
documentation.

## Permissions And Privacy

Future implementation PRs must document and test permission behavior before
shipping:

- Microphone access requires a user-facing usage description and sandbox
  audio-input entitlement review.
- Speech recognition may require its own usage description and permission prompt.
- Spoken output should not require microphone access.
- Raw audio should stay in memory only long enough to produce a transcript.
- Translation history may store the final transcript and translated text, but
  not audio buffers, partial hypotheses, or recognition debug data.
- Logs must not contain audio transcripts, translated text, recognition
  alternatives, provider prompts, or credentials.
- If any external speech service is added, update `docs/privacy.md`,
  `docs/app-identity-permissions.md`, settings copy, and release notes in the
  same implementation PR.

## UX Boundaries

- Voice capture should be an explicit command, not passive listening.
- The app should show recording, recognizing, translating, cancelled, denied,
  and failed states distinctly.
- The first pass should limit phrase duration to avoid accidental long captures.
- It should not attempt always-on listening, wake words, conversation mode,
  automatic language switching during speech, or background recording.
- It should not introduce a separate voice provider picker until an external
  speech service is approved.

## Implementation Slices

1. Add voice capture permission models and settings/onboarding copy.
2. Add a speech-to-text service abstraction and test double.
3. Wire push-to-talk transcript capture into Quick Translate.
4. Translate the transcript through existing provider routing and popup/history
   behavior.
5. Add spoken output controls after transcript translation is stable.

Each slice should be reviewable without including word-card or dictionary work
from issue `#32`.

Issue `#47` covers the first slice only: microphone and speech-recognition
permission states, recoverable setup copy, usage-description strings, and
documentation. It does not start live capture, enable background listening, add
the sandbox audio-input entitlement, or introduce a speech-to-text service.

## Test Expectations

- Permission baseline tests for microphone and speech-recognition requirements
  once those permissions are introduced.
- Service abstraction tests for success, cancellation, denied permission, empty
  transcript, and recognition failure.
- App model tests for recording, recognizing, translating, cancellation, and
  recovery states.
- History tests only if voice transcripts are persisted.
- No test should require live microphone input or call an external speech API.

No tests are needed for this planning-only document.
