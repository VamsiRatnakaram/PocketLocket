# PocketLocket

[![Tests](https://github.com/VamsiRatnakaram/PocketLocket/actions/workflows/tests.yml/badge.svg)](https://github.com/VamsiRatnakaram/PocketLocket/actions/workflows/tests.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-blue)

A private, **on-device** personal budgeting app for iPhone. The home screen is a
**spend-categorizing ring**. All of your financial data is stored **only on your
device** (SwiftData + Keychain) — there is no backend, no account to create, and
nothing is ever sent to a server we run.

Two ways to get bank data, both fully on-device:

| Source | Cost | Auto-sync | Notes |
|--------|------|-----------|-------|
| **SimpleFIN Bridge** | ~$15/yr | ✅ | Read-only by design. You log in on SimpleFIN's site; the app only receives a read-only access URL, which is stored in the Keychain behind Face ID. **Recommended.** |
| **File import (OFX/QFX/CSV)** | Free | ❌ manual | Download a statement from any bank and import it; parsed 100% on-device. |

```
        ┌──────────────────── iPhone (all data lives here) ────────────────────┐
        │  SwiftUI + Swift Charts UI                                            │
 SimpleFIN Bridge ─────▶  SwiftData store · Keychain (Face ID-bound token)      │
 Bank statement  ─────▶  on-device categorization · on-device Apple Intelligence │
        │                    ↓ precomputed snapshot (App Group)                 │
        │              Home Screen & Lock Screen widgets                        │
        └───────────────────────────────────────────────────────────────────────┘
                         (no backend · no server · no third-party data sharing)
```

- **UI:** SwiftUI + Swift Charts. Two switchable ring styles (donut, progress); animated rings and haptics.
- **Security:** Face ID / passcode lock, Keychain-stored token bound to biometrics, no data on external servers, read-only bank access.
- **Intelligence:** auto-categorization (merchant rules + heuristics) and **on-device Apple Intelligence** savings insights (iOS 26 Foundation Models; falls back to a rules engine when unavailable).
- **Data:** transactions + balances, mapped to friendly categories on-device.
- **Widgets:** Home Screen (small / medium / large) and Lock Screen widgets showing % of budget spent and the top categories, with a tap-to-cycle metric button. What they show and how to test them: [`ios/PocketLocketWidget/README.md`](ios/PocketLocketWidget/README.md).

---

## Repository layout

```
ios/                     SwiftUI app (Xcode project generated via XcodeGen)
  project.yml            project definition
  Config/*.xcconfig      build settings (Secrets.xcconfig is optional + git-ignored)
  Shared/                App Group snapshot layer compiled into BOTH targets
  PocketLocket/
    App/                 Entry point, RootView router, tabs, lock screen
    Core/
      Security/          KeychainStore, BiometricGate, SimpleFINStore
      Networking/        SimpleFINClient (talks to the bridge directly)
      Persistence/       AppModelContainer, SyncService
      Import/            OFX/QFX/CSV parsers + ImportService
      Widgets/           WidgetSnapshotPublisher (app → widget)
    Models/              SpendCategory, CategoryResolver, SpendAggregator,
                         AccountRecord, TransactionRecord, CategoryRule, …
    Features/            Home, Transactions, Accounts, Connect, Save, Settings
    Resources/           Info.plist, Assets
  PocketLocketWidget/    WidgetKit extension (views, provider, intent)
                         README.md — widget guide: what shows, how to test/debug
  PocketLocketTests/     unit + snapshot tests
  PocketLocketWidgetTests/ widget layout tests
scripts/bootstrap.sh     installs tooling + generates the project
docs/                    all documentation — start at docs/README.md
```

There is intentionally **no backend** — the app is entirely self-contained.

---

## Prerequisites

- macOS with **Xcode 27** (developed and CI-tested with Xcode 27.2; the release
  checklist targets the App Store Connect-supported release toolchain). The app's
  iOS 17 deployment target means older Xcode 26.x still builds it.
- *(Optional)* A **SimpleFIN Bridge** subscription for auto-sync: https://bridge.simplefin.org
- No Plaid, Supabase, or any other account is required.

Run the bootstrap once to install tooling (Homebrew, XcodeGen) and generate the
Xcode project:

```bash
bash scripts/bootstrap.sh
```

---

## Run it

```bash
open ios/PocketLocket.xcodeproj
```

Pick an iPhone simulator (or **My Mac (Designed for iPhone)** on Apple Silicon)
and press **Run**. On launch the app asks for Face ID / passcode, then opens to
the spend ring. Use the **＋** menu to add data.

### Connect a bank (SimpleFIN)

1. Get a one-time **setup token** at https://bridge.simplefin.org (create a
   bridge, connect your bank, copy the token).
2. In the app: **＋ → Auto-sync (SimpleFIN)**, paste the token, tap **Connect**.
3. The app claims a read-only access URL, stores it in the Keychain behind Face
   ID, and syncs. Pull-to-refresh (or reopen) to sync again.

### Import a statement (free)

**＋ → Import statement** and pick an `.ofx` / `.qfx` / `.csv` file. It is parsed
entirely on-device and merged into your data.

### Command line

```bash
cd ios
xcodegen generate            # required after adding/removing source files
# Build for the simulator
xcodebuild -project PocketLocket.xcodeproj -scheme PocketLocket \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
# Run the tests (app + widget bundles)
xcodebuild -project PocketLocket.xcodeproj -scheme PocketLocket \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

There are two schemes: **PocketLocket** (the app, plus both test bundles) and
**PocketLocketWidget** (the extension alone, for debugging its process).

The suite is green on both installed simulator runtimes. Pass `OS=` to choose
which one to test:

```bash
xcodebuild -project PocketLocket.xcodeproj -scheme PocketLocket \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.2' test
```

To make an **archive** (the `.xcarchive` you upload to App Store Connect), use
Xcode: select **Any iOS Device (arm64)** → *Product → Archive*, then
*Organizer → Distribute App → App Store Connect → Upload*. Don't archive against
a simulator or *My Mac (Designed for iPhone)*, and increment `CURRENT_PROJECT_VERSION`
in `project.yml` for each upload. Uploads must come from a **release** Xcode that
App Store Connect currently accepts.

> The full release procedure — including why a beta-built archive is
> unrecoverable and why `xcodebuild ... archive` produces a *development*-signed
> archive that App Store Connect rejects — lives in the maintainer's local
> release checklist (`docs/release/LOCAL_TESTFLIGHT_RELEASE.md`, git-ignored
> because it references account-specific values).

---

## Running on your iPhone

Signing is preconfigured (automatic, with the development team set in
`project.yml`; bundle id `com.vratnakaram.PocketLocket`). Connect your iPhone,
select it in Xcode, and Run. With a **free** Apple ID the install is valid for
**7 days** — re-run from Xcode to renew. On the device, first launch requires
trusting your developer certificate in **Settings → General → VPN & Device
Management**.

The app's deployment target is **iOS 17.0**, so the same binary runs on iOS 17
through 27 unchanged. See [docs/HANDOFF.md](docs/HANDOFF.md) §3 for the current
Xcode/SDK toolchain notes and simulator-runtime pinning caveats.

---

## Security model

- **No bank credentials on the device.** With SimpleFIN you authenticate on
  SimpleFIN's site; the app only ever receives a **read-only access URL**.
- **The access URL is Keychain-stored and biometric-bound.** It uses a
  `SecAccessControl` requiring user presence (Face ID / Touch ID / passcode) to
  read or replace, and `WhenUnlockedThisDeviceOnly` so it never syncs to iCloud.
- **Face ID / passcode** gates the app on launch and after backgrounding.
- **On-device intelligence.** Apple Intelligence insights run locally via
  Foundation Models — your spending never leaves the phone.
- **Transport security.** App Transport Security is on (HTTPS only); the app
  ships **no secrets** and talks only to the SimpleFIN bridge you connect.
- **Reset anytime.** *Settings → Reset local data* wipes all accounts,
  transactions, and connections from the device.

---

## Sharing with friends & family

The app needs no backend, so every install is fully self-contained (each person
uses their own SimpleFIN bridge or imports their own statements — nothing is
shared between installs). Distribution options:

- **This Mac / your own iPhone:** run from Xcode (free; 7-day signing on device).
- **TestFlight** (up to 10,000 testers via a private link): requires the paid
  Apple Developer Program ($99/yr).
- **App Store:** PocketLocket is being prepared for its App Store release —
  check back soon for the download link.
- **AltStore / SideStore:** free sideloading with weekly re-signing.

---

## Documentation

| Document | What it covers |
|----------|----------------|
| [docs/README.md](docs/README.md) | Index of all documentation, with audience and visibility notes |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contributor rules: setup, XcodeGen golden rule, tests, privacy invariants, PR rules |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Full technical breakdown: components, data/security model, flows, design decisions |
| [docs/HANDOFF.md](docs/HANDOFF.md) | Picking the project back up on another Mac: setup, everyday commands, current state |
| [ios/PocketLocketWidget/README.md](ios/PocketLocketWidget/README.md) | Widget guide: what each widget shows, how to add, test, and debug them |
| [privacy-policy/](privacy-policy/index.html) | Public privacy policy + support pages (served via GitHub Pages) |
| `docs/release/` | Release checklists and App Store copy (git-ignored — account-specific) |
