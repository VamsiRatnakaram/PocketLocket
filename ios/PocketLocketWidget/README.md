# PocketLocketWidget

The WidgetKit extension for PocketLocket: Home Screen (small / medium / large)
and Lock Screen widgets showing % of budget spent and the top categories, with
a tap-to-cycle metric button.

This target runs in its **own process** and cannot open the SwiftData store or
the Face ID–bound token, so the app publishes a small precomputed snapshot into
a shared **App Group** container whenever your data changes. The design
rationale — the publisher, the `Shared/` snapshot layer, the two-entry timeline,
and the key decisions — lives in
[`docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md) (see *The widget extension
and `Shared/*`). This file is the practical guide: what the widgets show, and
how to build, add, test, and debug them.

## What the widgets show

Add them by long-pressing the Home Screen → **＋** → search **PocketLocket**.
Small, medium and large sizes are available, plus circular and rectangular
Lock Screen widgets.

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

If the app hasn't run in a while, the widget says *"as of 3h ago"* instead of
pretending to be current.

> On a **physical device**, App Groups need the paid Apple Developer Program
> ($99/yr) — the entitlement is refused by a free personal team. The simulator
> works without it.

## Testing the widget

There is no "run the widget" button; WidgetKit launches the extension, not you.
So you test in layers, cheapest first.

### 1. Layouts — no simulator needed

The render tests draw every family and metric to PNGs you can actually look at:

```bash
cd ios
xcodebuild -project PocketLocket.xcodeproj -scheme PocketLocket \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PocketLocketWidgetTests test
open /tmp/widget_layouts
```

### 2. The real widget on the simulator

Build and run the app, then add the widget by hand — long-press the Home
Screen → **＋** → **PocketLocket** → drag a size onto the Home Screen. Adding a
widget is a drag gesture, so it can't be automated; everything after that can be.

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

### 3. Debugging the extension's own code

Select the **PocketLocketWidget** scheme and hit Run — Xcode shows *"Waiting for
the PocketLocketWidget process to launch"*. Trigger it by adding or rotating the
widget, and your breakpoints in `BudgetTimelineProvider` hit. This is the only
way to see inside the extension process.

### 4. On your phone

The widget needs the App Group entitlement, which a free personal team is
refused, so this step needs the paid program. Archive from Xcode with the paid
team selected and hand the build to yourself over **TestFlight** (see
[`docs/release/LOCAL_TESTFLIGHT_RELEASE.md`](../../docs/release/LOCAL_TESTFLIGHT_RELEASE.md)).
Then check the two behaviours that only show up on a real Home Screen: amounts
stay hidden until *Settings → Widgets → Show amounts*, and after ~6 hours
without opening the app the widget switches to *"as of Xh ago"*.
