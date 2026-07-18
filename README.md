# Budget App

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
        └───────────────────────────────────────────────────────────────────────┘
                         (no backend · no server · no third-party data sharing)
```

- **UI:** SwiftUI + Swift Charts. Two switchable ring styles (donut, progress); animated rings and haptics.
- **Security:** Face ID / passcode lock, Keychain-stored token bound to biometrics, no data on external servers, read-only bank access.
- **Intelligence:** auto-categorization (merchant rules + heuristics) and **on-device Apple Intelligence** savings insights (iOS 26 Foundation Models; falls back to a rules engine when unavailable).
- **Data:** transactions + balances, mapped to friendly categories on-device.

---

## Repository layout

```
ios/                     SwiftUI app (Xcode project generated via XcodeGen)
  project.yml            project definition
  Config/*.xcconfig      build settings (Secrets.xcconfig is optional + git-ignored)
  BudgetApp/
    App/                 Entry point, RootView router, tabs, lock screen
    Core/
      Security/          KeychainStore, BiometricGate, SimpleFINStore
      Networking/        SimpleFINClient (talks to the bridge directly)
      Persistence/       AppModelContainer, SyncService
      Import/            OFX/QFX/CSV parsers + ImportService
    Models/              SpendCategory, CategoryResolver, SpendAggregator,
                         AccountRecord, TransactionRecord, CategoryRule, …
    Features/            Home, Transactions, Accounts, Connect, Save, Settings
    Resources/           Info.plist, Assets
  BudgetAppTests/        unit + snapshot tests
scripts/bootstrap.sh     installs tooling + generates the project
docs/ARCHITECTURE.md     how it all fits together
```

There is intentionally **no backend** — the app is entirely self-contained.

---

## Prerequisites

- macOS with **Xcode 16.1+** (built and tested with Xcode 26).
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
open ios/BudgetApp.xcodeproj
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
# Build for the simulator
xcodebuild -project BudgetApp.xcodeproj -scheme BudgetApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
# Run the tests
xcodebuild -project BudgetApp.xcodeproj -scheme BudgetApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

---

## Running on your iPhone

Signing is preconfigured (automatic, with the development team set in
`project.yml`; bundle id `com.vratnakaram.BudgetApp`). Connect your iPhone,
select it in Xcode, and Run. With a **free** Apple ID the install is valid for
**7 days** — re-run from Xcode to renew. On the device, first launch requires
trusting your developer certificate in **Settings → General → VPN & Device
Management**.

> Running on an **iOS 27 beta** device needs the matching **Xcode 27 beta**;
> the iPhone simulator and "My Mac (Designed for iPhone)" work with current Xcode.

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
  Apple Developer Program ($99/yr). This is a private beta, **not** an App Store
  release.
- **AltStore / SideStore:** free sideloading with weekly re-signing.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for a full technical breakdown.
