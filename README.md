# PocketLocket

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
- **Widgets:** Home Screen (small / medium / large) and Lock Screen widgets showing % of budget spent and the top categories, with a tap-to-cycle metric button.

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
  PocketLocketTests/     unit + snapshot tests
  PocketLocketWidgetTests/ widget layout tests
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

### Home Screen & Lock Screen widgets

Long-press the Home Screen → **＋** → search **PocketLocket**. Small, medium and
large sizes are available, plus circular and rectangular Lock Screen widgets.

- **Small** — a budget ring with the headline metric, and a tap-to-cycle button
  (`% spent` → `left` → `safe to spend/day`).
- **Medium / large** — the ring plus the top categories with proportional bars.
  Each row opens that category's transactions in the app.
- **The ring is colored by category.** The arc still only fills to your budget
  percentage — length answers *"how much of my budget is gone"* — but the filled
  part is split into per-category segments using the same twelve tints as the
  rows, so color answers *"on what"*. The ring is the rows' legend: the medium
  widget lists three categories, so the ring names at most three, and anything
  beyond that (or trimmed off) is drawn as one pale neutral "unattributed"
  segment rather than being silently absorbed. Turn it off with
  *Settings → Widgets → Color ring by category* (on by default) to get the plain
  single-color ring back. Lock Screen widgets stay monochrome — Apple renders
  them in a context where color carries no information anyway.
- **Percentages by default.** Dollar amounts only appear if you turn on
  *Settings → Widgets → Show amounts*; with it off, the amounts are not just
  hidden, they are absent from the file the widget reads.
- Tapping a widget opens the app at **Home** — it never skips the Face ID prompt.

The widget runs in its own process and cannot open the SwiftData store or the
Face ID–bound token, so the app publishes a small precomputed snapshot into a
shared **App Group** container whenever your data changes. If the app hasn't run
in a while, the widget says *"as of 3h ago"* instead of pretending to be current.

> On a **physical device**, App Groups need the paid Apple Developer Program
> ($99/yr) — the entitlement is refused by a free personal team. The simulator
> works without it.

#### Testing the widget

There is no "run the widget" button; WidgetKit launches the extension, not you.
So you test in layers, cheapest first.

**1. Layouts — no simulator needed.** The render tests draw every family and
metric to PNGs you can actually look at:

```bash
cd ios
xcodebuild -project PocketLocket.xcodeproj -scheme PocketLocket \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PocketLocketWidgetTests test
open /tmp/widget_layouts
```

**2. The real widget on the simulator.** Build and run the app, then add the
widget by hand — long-press the Home Screen → **＋** → **PocketLocket** → drag a
size onto the Home Screen. Adding a widget is a drag gesture, so it can't be
automated; everything after that can be.

```bash
cd ios
xcodebuild -project PocketLocket.xcodeproj -scheme PocketLocket \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.2' \
  -derivedDataPath /tmp/pl-build build
xcrun simctl boot "iPhone 17"
open -a Simulator
xcrun simctl install booted \
  /tmp/pl-build/Build/Products/Debug-iphonesimulator/PocketLocket.app
xcrun simctl launch booted com.vratnakaram.PocketLocket
```

Two things worth knowing on the simulator: a fresh device has **no passcode**,
and `BiometricGate` deliberately lets the app open in that case rather than
locking forever. And you can verify the app→widget hand-off without any UI,
because the App Group container is just a folder on your Mac:

```bash
# Did the app publish a snapshot the widget can read?
GROUP=$(xcrun simctl get_app_container booted com.vratnakaram.PocketLocket groups)
ls -l "$GROUP/Library/Preferences/group.com.vratnakaram.PocketLocket.plist"
```

If the app runs but that plist is missing, nothing is reaching the widget —
that's a publish bug, not a widget bug. To watch the app itself start, add
`--console` to `simctl launch`.

Tapping a widget is also testable without a widget — the app registers the
`pocketlocket` URL scheme:

```bash
xcrun simctl openurl booted pocketlocket://widget/home
xcrun simctl openurl booted 'pocketlocket://widget/category?id=food'
```

The widget **gallery preview** (what you see while picking a widget) comes from
`BudgetTimelineProvider.sampleSnapshot`, so it renders without any data.

**3. Debugging the extension's own code.** Select the **PocketLocketWidget**
scheme and hit Run — Xcode shows *"Waiting for the PocketLocketWidget process to
launch"*. Trigger it by adding or rotating the widget, and your breakpoints in
`BudgetTimelineProvider` hit. This is the only way to see inside the extension
process.

**4. On your phone.** The widget needs the App Group entitlement, which a free
personal team is refused, so this step needs the paid program. Archive from
Xcode with the paid team selected and hand the build to yourself over
**TestFlight** (see *Running on your iPhone* below). Then check the two
behaviours that only show up on a real Home Screen: amounts stay hidden until
*Settings → Widgets → Show amounts*, and after ~6 hours without opening the app
the widget switches to *"as of Xh ago"*.

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

To make an **archive** (the `.xcarchive` you upload to App Store Connect):

```bash
cd ios
xcodebuild -project PocketLocket.xcodeproj -scheme PocketLocket \
  -destination 'generic/platform=iOS' -configuration Release \
  -archivePath build/PocketLocket.xcarchive archive
```

Or in Xcode: select **Any iOS Device (arm64)** → *Product → Archive*, then
*Organizer → Distribute App → App Store Connect → Upload*. Don't archive against
a simulator or *My Mac (Designed for iPhone)*, and increment `CURRENT_PROJECT_VERSION`
in `project.yml` for each upload. Uploads must come from a **release** Xcode that
App Store Connect currently accepts — a beta-built archive is rejected and can't
be repaired afterwards.

---

## Running on your iPhone

Signing is preconfigured (automatic, with the development team set in
`project.yml`; bundle id `com.vratnakaram.PocketLocket`). Connect your iPhone,
select it in Xcode, and Run. With a **free** Apple ID the install is valid for
**7 days** — re-run from Xcode to renew. On the device, first launch requires
trusting your developer certificate in **Settings → General → VPN & Device
Management**.

> **iOS 27** is fully supported. The app's deployment target is **17.0**, so the
> same binary runs on iOS 17 through 27 unchanged, and the suite is green on the
> **iOS 27.2** simulator. This Mac now has **Xcode 27.2 (27B52)** with the
> **iOS 27.2 SDK**, which satisfies the **April 2027** rule that uploads must be
> built with the iOS 27 SDK or later — no extra install needed.
>
> If you keep an older Xcode around for archiving, keep it alongside Xcode 27
> rather than replacing either, and archive on whatever release App Store Connect
> currently accepts (see `docs/LOCAL_TESTFLIGHT_RELEASE.md` for why a *beta*-built
> archive is unrecoverable).
>
> Passing `OS=` to `xcodebuild` pins a runtime: `name=iPhone 17` exists on 27.0
> and 27.2, but **not** on 26.5, so an unpinned `iPhone 17` destination now fails
> with "Unable to find a device matching".

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
