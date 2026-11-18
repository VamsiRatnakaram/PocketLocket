# Contributing to PocketLocket

Thanks for your interest in improving PocketLocket! This is a small,
privacy-first, on-device iOS app with **no backend, no telemetry, and no
third-party SDKs** — contributions must preserve that.

## Before you start

- Requirements: macOS with Xcode 27.x (the CI runs Xcode 27.2) and an iOS
  simulator runtime. The app targets iOS 17+.
- No accounts or services are needed — the app is fully self-contained.
- Set up: `brew install xcodegen`, then `cd ios && xcodegen generate`.

## The golden rule

`ios/PocketLocket.xcodeproj` is **generated and git-ignored**. Never hand-edit
it. The project is defined by `ios/project.yml`; after adding, deleting, or
renaming any Swift file, re-run:

```bash
cd ios && xcodegen generate
```

before building.

## Build & test

From the repo root:

```bash
xcodebuild -project ios/PocketLocket.xcodeproj -scheme PocketLocket \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

A PR is expected to leave the full suite green (~350 tests across
`PocketLocketTests` + `PocketLocketWidgetTests`). CI runs the same command
unsigned (`CODE_SIGNING_ALLOWED=NO`) and skips `UISnapshotTests`, which can
stall in headless environments — keep new snapshot tests in that class so CI
stays fast.

## Privacy invariants (non-negotiable)

These are the product. Changes that break them will not be merged:

1. **No new network calls** except through the existing optional SimpleFIN
   path (`Core/Networking/SimpleFINClient.swift`). If the user never enables
   SimpleFIN, the app must make zero network requests.
2. **No analytics, ads, crash reporters, or tracking SDKs.** No new third-party
   dependencies at all — the app has zero dependencies by design.
3. **Credentials stay in the Keychain.** The SimpleFIN access URL is
   Keychain-stored and biometric-gated; never persist it to defaults, files, or
   logs.
4. **Widgets cannot open the SwiftData store or the Keychain.** They read the
   precomputed snapshot the app publishes into the App Group (`Shared/`).
5. **Debug-only hooks stay `#if DEBUG`.** Anything that weakens the lock gate
   or seeds data (see `App/DebugLaunch.swift`) must be compiled out of Release
   and guarded by an allowlist where credentials could be involved.

## Housekeeping

- **Never commit secrets.** `ios/Config/Secrets.xcconfig`, everything under
  `docs/release/`, and `scripts/demo-token.txt` are git-ignored and must stay
  that way, even in a fork with different signing.
- New Swift files go under the existing layer structure (`App/`, `Core/`,
  `Models/`, `Features/`, `Shared/`) — see `docs/ARCHITECTURE.md` for where
  things belong and why.
- New user-facing strings: keep the in-app privacy policy
  (`Features/Settings/PrivacyPolicyView.swift`) and `privacy-policy/index.html`
  in sync if your change affects what data is stored where.

## Pull requests

- One concern per PR; describe the *why*, not just the *what*.
- Include tests for new logic — most of the codebase is plain Swift
  (`Models/`, `Core/`) and unit-testable without UI.
- CI must be green before review.
- If your change alters the UI, add or update a screenshot via
  `scripts/appstore-screenshots.sh` in the PR description when practical.

## License

By submitting a pull request you agree that your contribution is licensed
under the project's [MIT License](../LICENSE).
