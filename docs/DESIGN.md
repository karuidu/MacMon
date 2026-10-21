# Design notes

**English** · [简体中文](DESIGN.zh-CN.md)

Back to [README](../README.md).

This is the engineering log behind MacMon: the constraints that shaped the design,
the approaches that failed, and the measurements that settled the arguments. It is
deliberately more detailed than the README — if you are here to change the pager or
the collectors, read this first.

## Paging: the container is hand-rolled, not a `ScrollView`

The first implementation was the idiomatic one:

```swift
ScrollView(.horizontal) {
    LazyHStack(spacing: 0) {
        ForEach(DashboardPage.allCases) { page in
            PageView(page: page).containerRelativeFrame(.horizontal)
        }
    }
}
.scrollPosition(id: $currentPage)
```

It looked right and behaved wrong. On macOS 14, `scrollPosition(id:)` **follows
scrolling but does not drive it**: launching with `MACMON_PAGE=security` highlighted
the right pill in the top bar while the content stayed on page 1. Reproduced three
times in a row. `LazyHStack` compounded it — jumping to a page that had never been
instantiated failed silently.

The current `PagePager` is a plain `HStack` sized `width × 5`, moved with
`offset(x: -index × width + dragOffset)`:

- **Drag** — `DragGesture` with a horizontal test (`abs(dx) > abs(dy) × 1.5`) and
  `predictedEndTranslation` so a flick registers as a page turn.
- **Scroll** — `NSEvent.addLocalMonitorForEvents(.scrollWheel)`, accumulating 52 pt
  per page. The monitor must not consume vertical events, or lists stop scrolling.
- **Keyboard** — `⌘1`–`⌘5` and `⌘[` / `⌘]` mutate the same `NavigationModel.page`.

### Page width cannot come from a `GeometryReader` inside the content

Measured inside a `ScrollView`'s content, `GeometryReader` reports the *content*
width, not the viewport. With five pages at `width × 5`, the result is
`width × 25` and everything collapses. Either `containerRelativeFrame(.horizontal)`
or a `GeometryReader` wrapped *outside* the scroll content works.

### Navigation state lives apart from `AppModel`

`AppModel` publishes collection results every second. If menu commands capture it,
SwiftUI rebuilds the menu once per second and shortcuts intermittently stop
responding. `NavigationModel` is a separate `ObservableObject` that never changes
during a tick.

## First frame must not wait for full collection

The original startup ran the whole pipeline — 748 processes plus signature checks on
21 startup items — before publishing anything. The first few seconds were a full
screen of "warming up" and zeros.

Now the pipeline publishes in three stages:

1. Fast snapshot (~0.4 s) — CPU, memory, temperature, disk, network, battery
2. Process rows
3. Startup items (signature verification is the expensive part)

Three sequential stages on one serial queue, each hopping to the main actor as it
completes. The screen has real numbers within ~5 s even when the process scan is slow.

`AppModel.start()` is also idempotent (`guard timer == nil`). Recreating the window
re-runs `onAppear`; without the guard you get a second `Timer` and double the
collection load — which is easy to mistake for a leak.

## Layout traps

### `Spacer` competes with `frame(maxHeight: .infinity)`

In a hero card, a `Spacer` under the number plus `maxHeight: .infinity` on the
sparkline means the two split the remaining space. The chart ends up ten points tall
and looks like it failed to draw. Let only the chart absorb the leftover height.

### The sparkline range must be in the same unit as the number

The disk hero card stored *read/write throughput* as history but drew it against a
percentage axis. The range became 227 MB/s and the curve flattened against the
bottom. History now stores `usedPercent`.

Related: `Sparkline` supports a non-zero baseline
(`ratio = clamp((v − lower) / (upper − lower), 0, 1)`). Grid lines are drawn
**above** the area fill and below the stroke — draw them first and the fill washes
them out.

### Table headers and rows must share fixed column widths

With flexible columns, every row computes its own widths from its own content, so
rows drift out of alignment. `ProcessColumns` defines one set of widths used by
header and rows alike, with the remaining space given to the last column.

### Temperature sparkline: window centered on the current value

A fixed 0–110 °C axis puts a 38 °C reading at 35% height, which reads as "flat near
zero". Taking `min…max` of history is worse: one old 47 °C peak stretches the range
so the current value is pinned to the lower edge again.

`TempScale.range(for:current:)` therefore builds a window **centered on the current
value**, with a span of at least 8 °C, quantized to 5 °C so the axis does not shift
every second:

```swift
let span = max(hi - lo + 2, minSpan)
var lower = floor((cur - span * 0.5) / 5) * 5
var upper = ceil((cur + span * 0.5) / 5) * 5
```

The card prints the range (`40–50℃`); without it, a normal 2 °C wobble looks like a
dramatic swing. The ring gauge keeps the absolute 0–110 scale, because a ring has no
axis to label.

Temperature history must skip missing readings (`if let celsius = ... { append(...) }`)
rather than appending `0` as a placeholder — a zero pulls the computed lower bound
down permanently.

### `StackBar` with five segments

Two bugs, both fixed the same way:

- `id = UUID()` regenerated every second, so SwiftUI rebuilt every segment and
  animations restarted. The id is now the segment label.
- Zero-value segments still claimed horizontal space, producing gaps and wrong
  proportions. Zero segments are filtered out, and the bar distributes
  `width − gap × (n − 1)` across the *visible* segments.

## Windows: why "Open dashboard" did nothing

The menu bar panel originally did:

```swift
for window in NSApp.windows where window.canBecomeMain {
    window.makeKeyAndOrderFront(nil)
}
```

Clicking it after closing the window with the red button had no effect. The
assumption was "the window was destroyed, so we need to recreate it". That
assumption was wrong, and a scripted self-test (`--window-selftest`) proved it:

```
[启动后]        主窗口数=1 visible=true
[hide 之后]     主窗口数=1 visible=false     ← object still there, just not visible
[show 之后]     主窗口数=1 visible=true key=true
[模拟红叉关窗]  主窗口数=1 visible=false     ← same: not destroyed
[重建后]        主窗口数=1 visible=true key=true   ← always exactly one
```

The real cause: **`canBecomeMain` flips to `false` once a window is ordered out or
closed**, so the loop body never ran. The window identification predicate is now
just "has `.titled` and is not an `NSPanel`" — status bar windows have no title, and
the `MenuBarExtra` panel is an `NSPanel`, so those two conditions exclude everything
else.

Also note: a minimized window still reports `isVisible == true`. Any "is it visible"
check must be `window.isVisible && !window.isMiniaturized`, and must `deminiaturize`
before ordering front.

### `WindowGroup` → `Window(id:)`

`WindowGroup` is "open another window of this kind": clicking the menu bar item ten
times leaves ten dashboards. `Window("MacMon", id: WindowID.dashboard)` is a
singleton scene. The state that decides the button's label lives in
`WindowBridge`/`DashboardWindowState`, subscribing to
`didOrderOnScreen` / `didOrderOffScreen` / `didMiniaturize` / `didDeminiaturize` /
`didBecomeKey` and the app hide/unhide notifications.

Note that `NSWindow.didBecomeVisibleNotification` does not exist on macOS; use
`didOrderOnScreen`.

### Do not hide the dashboard with `NSApp.hide(nil)`

It hides the menu bar panel that is currently being clicked, which reads as "the
whole thing vanished on click". Use `window.orderOut(nil)`.

### Window placement must be clamped

macOS restores a window to its previous frame. After switching displays, the origin
can land outside the visible area — observed at `y = −122`, leaving half the window
off-screen. `place()` clamps at 0.15 s and again at 1 s after launch, because the
restore can happen after the first layout pass.

The size is forced **once per process**; afterwards only the origin is clamped.
Otherwise recreating the window resets a size the user deliberately dragged to.

## Startup item monitoring

### FSEvents instead of `DispatchSource` (vnode)

Watching a directory with a vnode source means an open fd per directory. If the
directory is deleted or replaced wholesale, the source is cancelled and the fd
becomes invalid; you must reopen and re-arm inside the cancel handler. Worse, the
callback does not tell you *which file* changed, so you rescan everything anyway.

`FSEventStreamCreate` over three paths is a single stream, needs no fd management,
and events carry concrete paths. A replaced directory produces a single
`RootChanged` event, which is exactly the signal to rescan.

Latency is 0.4 s (events are already coalesced by the kernel at that granularity).
The diff runs on a 1.0 s tail debounce with a 3.0 s hard cap — without the cap, a
large copy keeps resetting the timer and the user waits indefinitely.

A 60-cycle polling fallback covers dropped events: waking from sleep and a backlogged
queue both lose FSEvents.

### The diff key must be `plistPath`, not `StartupItem.id`

`StartupItem.id` is `kind|label`. Two plists with the same `Label` in different
directories collide and overwrite each other. And renaming a `Label` would be
reported as "one removed + one added" when it was a rename.

### `unavailableKinds`: the false-alarm avalanche

`try? FileManager.contentsOfDirectory` returns `nil` both when the directory is
unreadable and when it does not exist — indistinguishable from "the directory is
empty". A single transient read failure produced a dozen "startup item removed"
alerts.

`StartupSnapshot` therefore carries `unavailableKinds`, and the diff skips add/remove
decisions for those categories. Verified by `mv`-ing all of `~/Library/LaunchAgents`
away: the change count stayed **exactly** the same, and restoring it produced no
phantom "added" records either.

### The first scan seeds a baseline and never alerts

`startup` starts as an empty snapshot. Diffing against it would emit twenty-odd
"new startup item" alerts on first launch. The first scan is baseline-only.

## Memory accounting derivation

Activity Monitor's four numbers, taken from a screenshot at one instant:

```
App Memory   8.03 GB
Wired        1.47 GB
Cached Files 11.39 GB
Free         3.11 GB   (implied)
Total       24.00 GB
```

Solving for the correct decomposition:

```
used = 8.03 + 1.47 = 9.50 GB          (Activity Monitor's "Memory Used")
used = internal + wired + compressed   →  internal = 8.03 + purgeable
app  = internal − purgeable      = 8.03
cached = external                = 11.39
free = 24.00 − 9.50 − 11.39      = 3.11
```

The self-check closes: `8.03 + 11.39 + 1.47 + 0 + 3.11 = 24.00`.

Two nearby formulas are self-consistent but wrong for this UI:

- `used = app + wired + compressed` under-reports by exactly `purgeable` (0.8 GB here).
- `cached = external + purgeable` double-counts purgeable, since it is already inside
  `internal` and therefore already subtracted from `app`.

`used` must be `internal + wired + compressed`, keeping `purgeable` inside `used`.
That is why the diagnose self-check sums **App + purgeable + cached + wired +
compressed + free** — the six components are mutually exclusive and exhaustive.

The `vm_stat` page counts are in pages, so multiply by `vm_page_size`, and use
saturating subtraction (`internal > purgeable ? internal - purgeable : 0`) so a
transient inconsistency cannot underflow into a huge `UInt64`.

Also `mach_host_self()` returns a send right that must be released with
`mach_port_deallocate`; skipping it leaks a port per sample, i.e. one per second.

## Notifications

`requestAuthorization` succeeds once per bundle ID. Asking during launch and having
the user reflexively decline disables the feature permanently, so the request is
only made when the user turns the switch on.

`UNUserNotificationCenter.current()` throws `bundleProxyForCurrentProcess is nil`
when there is no bundle — which is exactly the case for `swift run` or a bare binary.
Every access is behind `Bundle.main.bundleIdentifier != nil`, and
`AppDelegate.applicationDidFinishLaunching` returns early in that case.

`willPresent` must return `[.banner, .list, .sound]`. Without it, notifications are
delivered but invisible while the app is frontmost, which looks identical to "the
feature does not work".

## Risk scoring

Two engines, one score type:

**Processes** (`ProcessRiskEngine`) skip signature verification for anything under
`/System`, `/usr/*`, `/bin`, `/sbin`, `/Library/Apple` — those binaries ship with
the OS. The rest get a global verification budget (`verifyBudget: 50`) so a 748-row
scan cannot block the loop. Rules: suspicious path (`/tmp`, `/var/folders`,
`/Library/Caches`) +40, masquerading as a system component +35, unsigned/invalid +35,
ad-hoc +30.

**Startup items** (`StartupCollector.assess`) weight executable risk more heavily,
because a startup item runs unattended at every boot. Full table is in the README.

Levels are cut from the capped sum: `<20` none, `20–39` low, `40–64` medium,
`65–84` high, `85+` critical.

Killability is pre-computed in the collector so the UI can disable the button instead
of letting the user click and get an error: pid ≤ 1, self, blacklisted names
(`windowserver`, `launchd`, `coreaudiod`, …), foreign owner, or kernel thread.

## Menus: what SwiftUI leaves behind

`CommandGroup(replacing:)` empties a *group*, not the top-level menu that holds it.
Removing `.textFormatting`, `.toolbar` / `.sidebar` and `.help` therefore left three
empty shells behind — a Format, View and Help menu with nothing in them. On top of
that, macOS injects items into the Edit menu (AutoFill, Start Dictation…, Emoji &
Symbols) and a window list into the Window menu, and none of that goes through
SwiftUI's command builder.

So the menu is pruned a second time, after construction (`App/MenuLayout.swift`):

- drop the top-level menus that map to abilities this app does not have (Format,
  Window, Help), and nil out `NSApp.windowsMenu` / `NSApp.helpMenu` so AppKit does not
  repopulate them;
- drop the injected text-input items;
- put one item back into View — Enter Full Screen (⌃⌘F) — because emptying the toolbar
  group took the system's own full-screen item with it;
- collapse consecutive and leading/trailing separators.

Two details worth knowing:

- **Ten children is the ceiling.** `CommandsBuilder` accepts at most ten; eleven groups
  fail with `extra argument in call`. The fix is two `.commands { }` blocks on the same
  scene, not a nested group.
- **System menu titles follow the system language, not the app's.** With the UI switch
  set to English, About / Hide / Quit and Edit / View stayed Chinese, so `MenuLayout`
  renames them too — matching the **action selector** (which does not change with
  locale) and not the title, which does. Pruning runs three times after launch
  (SwiftUI assembles menus asynchronously) and once more on every language switch.

Note that the `Services` submenu is gone entirely. Every item in it came from another
app: with Xcode installed you get four Instruments templates (Activity Monitor,
Allocations & Leaks, File Activity, System Trace), injected into *every* app's menu by
the system services registry. MacMon registers none — its `Info.plist` has no
`NSServices` — so the submenu was only ever a doorway into someone else's app.

## Icon rendering

`assets/make-icon.swift` is a plain `swift file.swift` script over Core Graphics — no
Skia, no SVG toolchain, no extra dependency, which keeps the "clone and build" story
true.

Three things bit during the first attempts:

- **Flipping y inverts arc angles.** The whole drawing is translated and scaled so
  coordinates read as top-left origin, which also mirrors `addArc`'s angle direction.
  An arc specified as 138° → −42° came out somewhere else entirely. The script now
  samples the arc into a polyline with explicit visual angles
  (`x + r·cos θ`, `y − r·sin θ`) and strokes that; no mental gymnastics needed.
- **A linear gradient stops dead at its end point.** The diagonal sheen was clipped to
  a rect, and because the gradient did not extend past `end`, it left a visible hard
  edge across the tile. Radial gradients have no such edge; that is what the sheen is
  now.
- **The gradient stroke needs `sourceIn` over the whole path bounding box.** Stroking
  in white inside a transparency layer and then compositing a gradient with
  `sourceIn` gives a gradient stroke — but only if the gradient covers the entire
  path, otherwise the uncovered part stays white.

Small sizes are rendered from a **simplified path**, not downsampled: at 16–32 px the
two small waves of a realistic ECG collapse into blobs, so `build-icon.sh` renders
each size separately and the generator drops them below 32 px, thickening the stroke
at the same time.

## Verification tooling

There is no test target. Four scriptable entry points stand in for one:

- `--diagnose` prints every collector's real output plus cross-checks
  (`CProc` readability, memory self-check drift, process parse counts).
- `--window-selftest` drives the window lifecycle and prints state after each step.
- `--menus` prints the live `NSApp.mainMenu` tree — titles, shortcuts, nesting — then
  exits. Menus cannot be opened by a script without Accessibility permission, but they
  can be read, which makes "is the Services submenu really gone" a checkable claim
  instead of a screenshot someone has to eyeball.
- `scripts/check-l10n.py` parses the `en` dictionary and every `L.t("…")` / `L.f("…")`
  call site, then fails on a key that is used but untranslated, or on one whose `%@`
  count differs from its translation. A missing key is silent at runtime (the table
  falls back to Chinese), so this is the only automated guard on coverage. Parsing the
  dictionary needs care: long translations wrap onto a second line, and a
  line-anchored regex silently misses them — it reported 12 phantom gaps on a table
  that was in fact complete.

`.github/workflows/ci.yml` gates on the two headless-safe entry points (`--diagnose`,
plus the build and package checks) and runs the GUI-dependent ones
(`--menus`, `--window-selftest`) with `continue-on-error`, since a GitHub macOS runner
has no guaranteed `WindowServer` session. Assertions are structural — every section
printed, process count positive, memory parts within ±3% — because the runner is a VM
with no battery and no HID sensors.

For screenshots, `screencapture -l <windowID>` (with the id from
`CGWindowListCopyWindowInfo`) captures just the window plus its shadow, so system
notification banners and other apps never end up in the image. Note that on
multi-display setups `screencapture -x` only captures the main display; pass `-D 2`
for the secondary one.

One caveat when running helper binaries: an ad-hoc signed binary placed in `/tmp`
scores 80 by this app's own engine (ad-hoc +30, suspicious path +40, and other
rules), so it shows up in the "high-risk processes" list in your own screenshots.
Move helper tools out of `/tmp` when capturing.

## Memory notes / build gotchas

- `swift build` on this machine occasionally fails with
  `sandbox-exec: sandbox_apply: Operation not permitted` — that is SwiftPM's own
  sandbox nesting, not a code problem. `swift build --disable-sandbox` works.
- `Package.swift` pins Swift 5 language mode
  (`-strict-concurrency=minimal`) because the collectors are full of C interop and
  background queues, where Swift 6 strict concurrency produces noise unrelated to
  the actual data races.
