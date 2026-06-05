# Contribution Notes

These notes keep implementation work easy to continue across Codex chats and
easy to review in GitHub.

## Before Editing

- Fetch the requested base branch first. If that branch does not exist, verify
  the live remote state and use the repository default branch only when it is
  clearly the available source of truth.
- Read the relevant GitHub issue body before implementing.
- Check the working tree for unrelated changes.

## While Editing

- Keep changes scoped to the issue or PR slice.
- Prefer small files and explicit service boundaries.
- Put business logic in `LinguistMacCore`.
- Keep UI code in the app target.
- Add tests when the behavior has state, branching, permissions, persistence,
  network boundaries, or privacy impact.
- Do not copy source, assets, UI text, scripts, test code, or architecture from
  the GPL reference project.

## Before Committing

- Re-check `git status`.
- Inspect the diff.
- Run the focused tests for the changed behavior.
- Run broader validation before pushing a PR.

## Commit And Review Shape

- Commit by issue or review finding.
- Do not bundle unrelated findings into one large commit.
- Use PR bodies that link issues with closing keywords when merge should close
  them.
- Include validation commands and any skipped checks.

## Suggested Local Validation

Start narrow and expand:

```sh
xcodebuild -project LinguistMac.xcodeproj -scheme LinguistMac -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO ENABLE_TESTABILITY=YES test
xcodebuild -project LinguistMac.xcodeproj -scheme LinguistMac -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Before a PR, also run the CI-equivalent commands documented in
`docs/ci-cd.md` when local tooling is available.
