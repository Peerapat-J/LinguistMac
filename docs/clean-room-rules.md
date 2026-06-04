# Clean-Room Rewrite Rules

LinguistMac is a fresh implementation of a macOS screen translation app. The
reference repository is useful for product behavior, but its GPLv3 source,
assets, and implementation structure must not be copied into this project.

This document is an engineering guardrail, not legal advice.

## Allowed Reference Material

Use these sources to understand product behavior:

- Public README, CHANGELOG, release notes, and project descriptions.
- Public screenshots or user-provided screenshots.
- User-provided requirements written in this repository or in GitHub issues.
- Independently written notes that describe behavior without code-level detail.
- Public documentation for Apple, DeepL, Google Cloud Translation, Microsoft
  Azure Translator, GitHub Actions, Swift, and other APIs used directly here.

## Disallowed Material

Do not copy or translate these into LinguistMac:

- Source files from the reference project.
- Test code from the reference project.
- Build scripts, CI scripts, signing scripts, or generated files from the
  reference project.
- UI strings, icon artwork, images, fonts, layout constants, window behavior
  constants, or custom assets from the reference project.
- File organization, type names, protocol names, dependency graph, or internal
  implementation architecture from the reference project.
- Line-by-line behavior inferred from source code.

## Implementation Rules

- Implement behavior from first principles in this repository.
- Keep platform wrappers thin and testable.
- Put product logic in `LinguistMacCore`.
- Keep UI presentation in the app target.
- Add focused tests for each behavior as it lands.
- Prefer public API documentation over reverse-engineering the reference
  project.
- Document any uncertain feature before implementing it.

## PR Review Checklist

Every implementation PR should answer:

- Which GitHub issue or milestone does this close or advance?
- Which behavior was implemented?
- Which public/product source describes that behavior?
- Which tests cover the behavior?
- Was any GPL source, asset, script, UI text, or architecture copied? The
  expected answer is no.
- Were privacy-sensitive paths reviewed for clipboard, permissions, API keys,
  network calls, or captured text?

## Commit Discipline

Keep commits scoped. If review feedback reports multiple unrelated findings,
fix and push them as separate commits so each finding can be inspected without
being mixed into a larger change.
