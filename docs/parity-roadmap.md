# Parity Roadmap

This roadmap maps the clean-room implementation sequence to GitHub milestones
and issues. The first goal is behavior parity without copying GPL source,
assets, UI text, implementation structure, or scripts.

## M0 Foundation + Clean-Room Baseline

Goal: make future work safe, testable, and reviewable.

- `#1` `[M0][app] Scaffold macOS SwiftUI project` - completed scaffold.
- `#2` `[M0][architecture] Set up project structure and module boundaries` -
  define core models, service protocols, and dependency injection.
- `#3` `[M0][app] Configure identity, entitlements, and permission baseline` -
  add app metadata and permission posture.
- `#4` `[M0][ci] Add GitHub Actions CI for build and tests` - completed CI.
- `#5` `[M0][clean-room] Add rewrite documentation and feature inventory` -
  document clean-room rules and parity scope.
- `#6` `[M0][tests] Add test target, mocks, and validation fixtures` - add
  test doubles and focused baseline tests.

## M1 Menu Bar + UI Shell

Goal: create app surfaces before complex behavior.

- `#7` menu bar app shell.
- `#10` settings window shell.
- `#11` translation popup shell.
- `#12` Quick Translate panel shell.
- `#13` onboarding and status surfaces.

## M2 Screen Translation MVP

Goal: first end-to-end selected-region translation.

- `#14` region selection overlay and screen capture service.
- `#15` Apple Vision OCR and text preprocessing.
- `#16` Apple Translation coordinator.
- `#17` language selection, swap, auto-detect, and pack status.
- `#18` wire end-to-end screen translation flow.

## M3 Text Selection + Shortcut Input Modes

Goal: add non-OCR input workflows.

- `#19` configurable global shortcuts.
- `#20` selected-text translation workflow.
- `#21` double-copy clipboard translation trigger.
- `#22` drag/text capture translation mode.

## M4 Settings + Translation Providers

Goal: complete user-configurable provider parity.

- `#23` persisted user preferences and defaults.
- `#24` BYOK provider architecture.
- `#25` secure API key storage.
- `#26` launch at login, app language, and auto-copy settings.

Implementation notes and defaults live in `docs/m4-settings-providers.md`.

## M5 History + UX Polish + Release Readiness

Goal: finish daily-use polish and release posture.

- `#27` SwiftData translation history and recent menu.
- `#28` popup resizing, width, font, and position polish.
- `#29` user-facing errors and recovery paths.
- `#30` privacy posture and no telemetry/update assumptions.
- `#31` signing, notarization, and distributable artifact workflow.

Implementation notes and release guardrails live in `docs/privacy.md`,
`docs/release-checklist.md`, and `docs/ci-cd.md`.

## M6 Future Differentiation After Parity

Goal: keep non-parity ideas out of the critical path until parity is stable.

- `#32` word card and dictionary planning. Requirements and scope live in
  `docs/m6-word-card-dictionary.md`.
- `#33` speech or voice translation planning.

## Review Strategy

M0 can be reviewed in one PR because the open M0 issues are a single foundation
slice. Keep commits separated by issue:

- docs commit for `#5`
- architecture commit for `#2`
- tests/mocks commit for `#6`
- identity/permissions commit for `#3`

If a later milestone has independent user-facing surfaces, split PRs by workflow
or review risk rather than forcing all issues into one branch.
