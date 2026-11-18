# PocketLocket — Documentation index

Start here to find the right document. The top-level
[README](../README.md) covers what the app is and how to run it; these docs go
deeper.

## Committed docs (public)

| Document | Audience | What it covers |
|----------|----------|----------------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Reviewers, future maintainers | Components, data/security model, end-to-end flows, key design decisions |
| [../CONTRIBUTING.md](../CONTRIBUTING.md) | Outside contributors | Setup, the XcodeGen golden rule, test expectations, privacy invariants, PR rules |
| [HANDOFF.md](HANDOFF.md) | You, on a new Mac | Moving the project to another machine, prerequisites, first-time setup, everyday commands, current state |
| [../ios/PocketLocketWidget/README.md](../ios/PocketLocketWidget/README.md) | Anyone working on widgets | What each widget shows; how to add, test (layout render tests, simulator, URL scheme), and debug the extension process |
| [../privacy-policy/README.md](../privacy-policy/README.md) | Release prep | Publishing the privacy policy + support pages via GitHub Pages for App Store Connect |

## `release/` — git-ignored (private)

These reference the real Apple Team ID and account-specific copy. They are
listed in `.gitignore` and must **never** be committed or pasted into a public
repo. Back them up outside the repo (see `release/OPEN_SOURCE_HANDOFF.md` §1).

| Document | Audience | What it covers |
|----------|----------|----------------|
| [release/LOCAL_TESTFLIGHT_RELEASE.md](release/LOCAL_TESTFLIGHT_RELEASE.md) | You, at release time | Signing, App Store Connect record, toolchain/SDK rules, archive & upload, TestFlight |
| [release/APP_STORE_RELEASE_KIT.md](release/APP_STORE_RELEASE_KIT.md) | You, filling in ASC | Every piece of listing copy and questionnaire answer (name, subtitle, description, privacy answers) |
| [release/OPEN_SOURCE_HANDOFF.md](release/OPEN_SOURCE_HANDOFF.md) | You, when going public | Status of the history scrub and the remaining steps to make the repo public |

If you add a file here, add a `.gitignore` entry for it too — the whole point of
this folder is that its contents stay local.

## `assets/`

Logo candidates and other doc imagery.
