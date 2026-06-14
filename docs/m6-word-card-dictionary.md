# M6 Word Card And Dictionary Plan

This document scopes post-parity word-card and dictionary work for issue `#32`.
It is a planning gate, not an implementation spec for the first parity release.

## Product Goal

Help users understand individual terms after a translation without leaving the
current workflow. A word card should explain a selected source word in context
while preserving the full sentence translation as the primary result.

The first target user is someone who translates a sentence, recognizes most of
it, and wants to inspect one unfamiliar word. The word card should answer that
single-word question quickly instead of turning the popup into a full dictionary
application.

## Candidate Surfaces

- Translation popup: a compact card opened from a word in the existing Words
  section.
- Translation history: previous results may reopen the card if the underlying
  result still has word-level metadata.
- Quick Translate: eligible only after the popup interaction is stable, because
  typed text has different editing expectations.
- Menu bar: out of scope for the first pass; it can link to recent translation
  history but should not become a dictionary browser.

## Current Starting Point

PR `#43` added selected-text word breakdowns as additive metadata on the full
translation result. That metadata is enough to render the current Words section,
but it is not a dictionary-entry model.

Future work should avoid overloading `WordTranslation` with dictionary fields.
The card needs its own model so it can represent loading, empty, provider
failure, definition, example, and persistence decisions without changing the
meaning of the existing word breakdown.

## First-Pass Requirements

- Open a card for one source word from a translated sentence.
- Show the source word, its best short translation, and the sentence context.
- Keep the full sentence translation visible and authoritative.
- Make missing dictionary data a graceful empty state rather than a failed
  translation.
- Avoid saving sensitive lookup failures or raw provider diagnostics in history.
- Keep the default path on-device or already-selected-provider only; no new
  network destination should be introduced implicitly.

## Data Source Decision

The implementation must choose one of these paths before code starts:

| Option | Benefit | Risk or cost |
| --- | --- | --- |
| Existing translation provider prompt | Reuses configured engines and language routing | Cloud providers may receive extra text; prompt shape and costs need review |
| Apple system language APIs | Preserves the private default posture | Dictionary-level output may be limited or language-dependent |
| Bundled/local dictionary data | Predictable offline behavior | Licensing, app size, updates, and language coverage need review |
| External dictionary API | Rich definitions and examples | Adds a new data processor, key management, costs, and privacy disclosure |

The recommended first implementation is provider-backed lookup through the
already selected translation provider, with Apple Translation remaining the
default where possible. A separate external dictionary API should require its own
issue because it changes privacy, licensing, settings, and failure modes.

## Storage And Privacy

- Persist only display-ready lookup content that the user already saw.
- Do not persist provider prompts, raw responses, API keys, request IDs, or
  debug traces.
- If a cloud provider is selected, the lookup should use the same opt-in data
  flow documented for translation text.
- If a future external dictionary service is added, update `docs/privacy.md`,
  `docs/app-identity-permissions.md`, settings copy, and release notes in the
  same implementation PR.
- Treat source sentence context as translation content; it must follow the same
  logging and history rules as existing translation results.

## UX Boundaries

- The card should be compact enough to fit inside the popup without hiding the
  sentence translation.
- It should support dismissing and switching between words without re-running
  the full translation.
- It should not introduce spaced-repetition study, vocabulary lists, bookmarks,
  pronunciation, or quiz behavior in the first pass.
- It should not block screen, selected-text, double-copy, drag, or quick
  translation parity.

## Implementation Slices

1. `#46` add a lookup model and provider-facing abstraction for one word in
   sentence context.
2. `#53` render the card from the existing popup Words section with loading,
   success, empty, and error states.
3. `#56` persist display-ready card content in history only after the card has
   been shown.
4. `#48` consider Quick Translate and richer dictionary fields after the popup
   flow is proven.

Each slice should be reviewable without including voice translation work from
issue `#33`.

## Test Expectations

- Model tests for card state, serialization, and redaction boundaries.
- Coordinator tests for successful lookup, missing data, provider failure, and
  cancellation.
- Popup view model or state tests where card selection changes result state.
- Persistence tests only if display-ready card content is saved to history.

No tests are needed for this planning-only document.
