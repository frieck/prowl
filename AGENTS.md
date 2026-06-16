# PRowl — Agent Guide

This document is the source of truth for **how this repo is built** and **what patterns agents must follow**. Read it before making architectural changes.

PRowl is a **sandboxed macOS menu-bar app** (SwiftUI + AppKit, macOS 13+) that polls GitHub for open PRs and sends local notifications on status changes. The **Mac App Store** is the shipping target; local `./build.sh` is for day-to-day development only.

---

## Golden rules

1. **No hacks.** If a solution requires runtime class swizzling, private APIs, undocumented behavior, or “works on my machine” signing tricks, do not ship it. Find the App Store–safe pattern or ask.
2. **App Store build is authoritative.** `./build.sh` is a convenience wrapper. Behavior must remain correct when built via `project.yml` → Xcode → `./release.sh`.
3. **Stay sandboxed in release.** The App Store build always uses `PRowl/PRowl.entitlements`. Never weaken sandbox, disable hardened runtime, or add entitlements without justification.
4. **Minimal diffs.** Match existing naming, file layout, and abstraction level. Extend before inventing.
5. **Do not commit** unless the user explicitly asks.

---

## Architecture

```
Sources/PRowl/
  PRowlApp.swift              @main SwiftUI App (Settings scene stub only)
  AppDelegate.swift           Launch wiring, notification delegate lifecycle
  AppCoordinator.swift        Shared poller + open-settings closure
  StatusBarController.swift   NSStatusItem + NSPopover (AppKit)
  Models/PullRequest.swift    PRStatus, NotificationEvent, WatchSet
  Services/
    GitHubClient.swift        GraphQL client (configurable endpoint)
    KeychainStore.swift       PAT in Keychain (never UserDefaults/plaintext)
    PRPoller.swift            Timer, diffing, notification triggers
    NotificationManager.swift UNUserNotificationCenter wrapper
  Views/
    MenuContentView.swift     Popover UI (PR list + inline settings)
    SettingsView.swift        Configuration sections (embedded in popover)
    PopoverUIState.swift      Toggles popover between list and settings modes
    GlassSupport.swift        Liquid Glass helpers (macOS 26+ gated)
Resources/Info.plist          Bundle metadata, LSUIElement
PRowl/PRowl.entitlements      Sandbox (App Store / Xcode only)
project.yml                   XcodeGen spec for release archive
Package.swift                 SPM target for Cursor / ./build.sh
```

### UI split (intentional)

| Surface | Role |
|--------|------|
| **Popover** (`StatusBarController` + `MenuContentView`) | PR list, refresh, quit, and **inline settings** (gear toggles `PopoverUIState.showingSettings`) |
| **SettingsView** | Configuration sections embedded inside the popover — not a separate window |

Notification taps call `StatusBarController.openSettingsInPopover()` so the same inline settings screen opens in the panel.

**Do not** use runtime window hacks (`object_setClass`, etc.) to force keyboard focus in the popover. NSPopover is not a key window by design; token entry may require clicking the field or pasting via context menu.

### Menu-bar controller

- Use **`NSStatusItem` + `NSPopover`**, not `MenuBarExtra`, so **left and right click** both open the panel.
- Popover **`behavior = .transient`** — click outside or status item again to close.
- On show: `NSApplication.shared.activate(ignoringOtherApps: true)` then `popover.show(...)`.
- Implement **`NSPopoverDelegate`** (`popoverShouldClose`) when needed; do not replace the popover window class.

### State & coordination

- **`PRPoller`** is the single source of truth for PR data, settings (UserDefaults), and polling.
- **`AppCoordinator.poller`** is set once at launch in `AppDelegate`.
- **`@MainActor`** on UI controllers and `PRPoller`; network work stays `async`.

### Notifications

- Use **`UNUserNotificationCenter`** only (not deprecated `NSUserNotificationCenter`).
- **`NotificationManager`** is the sole owner; set `center.delegate = self` in `init` and **re-bind in `applicationDidBecomeActive`** (SwiftUI can clobber the delegate).
- Request authorization on **user interaction** (panel or settings window open), not only at launch.
- Implement **`userNotificationCenter(_:willPresent:withCompletionHandler:)`** so banners show while the app is active.
- Gate PR notifications in **`PRPoller.detectChanges`** — first poll seeds silently; only diffs after that fire alerts.
- Deliver with **`UNNotificationRequest`**; `trigger: nil` is acceptable for immediate local notifications on macOS.

### Secrets

- **Personal access token** → **`KeychainStore`** only (never UserDefaults/plaintext).
- **GitHub CLI mode** → run the user's installed `gh` (`gh auth token` / `gh auth status`); do not bundle `gh`. Same GraphQL bearer token `gh` already uses.
- Auth method persisted in UserDefaults (`GitHubAuth.method`); **`KeychainStore`** reads `keychain-access-groups` from live entitlements via `SecTaskCopyValueForEntitlement`; when absent (ad-hoc local build), it uses the default keychain. Do not hard-code team prefixes.

### Liquid Glass

- Helpers live in **`GlassSupport.swift`**.
- Always gate macOS 26 APIs with `#available(macOS 26.0, *)` and provide fallbacks for macOS 13–25.

---

## Build & signing (two paths)

### Local development — `./build.sh`

- Compiles via **Swift Package Manager** (`swift build`).
- Assembles **`PRowl.app`** manually (Info.plist, icons, resources).
- **Ad-hoc signs** with `codesign --sign -` **without entitlements**.
- **Why no entitlements locally:** ad-hoc signing does not resolve `$(AppIdentifierPrefix)` in `keychain-access-groups`, which causes **launch failure (POSIX 163)**. This is expected; do not “fix” by stripping sandbox from the release entitlements file.

### App Store / archive — `./release.sh`

- Requires **full Xcode** and `DEVELOPMENT_TEAM=…`.
- Regenerates **`PRowl.xcodeproj`** from **`project.yml`** (XcodeGen).
- Archives with **`PRowl/PRowl.entitlements`**, hardened runtime, proper team signing.
- Exports via **`ExportOptions.plist`** (`method: app-store`).

### DMG — `./dmg.sh`

- Runs `./build.sh`, optionally re-signs with **Developer ID** for distribution outside the App Store.
- Ad-hoc DMG is for personal testing only; App Store submission uses `release.sh`, not `dmg.sh`.

**After adding Swift files:** run `./scripts/generate-xcodeproj.sh` so the Xcode project stays in sync.

---

## App Store compliance checklist

When reviewing or implementing features, verify:

| Requirement | Project approach |
|-------------|------------------|
| App Sandbox | `com.apple.security.app-sandbox` in `PRowl.entitlements` |
| Network | `com.apple.security.network.client` only (no server entitlement) |
| Keychain | `keychain-access-groups` with `$(AppIdentifierPrefix)br.com.farsystems.prowl` |
| Hardened Runtime | `ENABLE_HARDENED_RUNTIME: YES` in `project.yml` |
| No private APIs | Public AppKit / SwiftUI / UserNotifications / Security only |
| Agent app | `LSUIElement` = true in `Info.plist` (menu-bar accessory, no Dock icon) |
| Icons | `AppIcon.appiconset` via `scripts/prepare-appiconset.sh`; menu glyph is template PNG |
| Single bundle ID | `br.com.farsystems.prowl` everywhere (Info.plist, entitlements, keychain service) |

**Entitlements policy:** only add new entitlements if the feature cannot work without them. Document why in the PR/commit message. App Store review rejects unnecessary entitlements.

**Not allowed for App Store builds:**

- Runtime `object_setClass` / method swizzling on system windows
- Loading arbitrary executables or disabling sandbox
- Storing credentials outside Keychain
- Hot-patching signed bundles post-build

---

## Forbidden patterns (learned the hard way)

These were tried and **must not be reintroduced**:

### 1. `object_setClass` on NSPopover windows

**Problem:** Forces `canBecomeKey` on the popover window so SwiftUI text fields accept keyboard input.

**Why forbidden:** Breaks transient popover dismissal (panel cannot close), relies on undefined runtime behavior, not App Store safe.

**Correct approach:** Keep configuration inline in the popover via `SettingsView` + `PopoverUIState`.

### 2. Ad-hoc sign + sandbox entitlements in `./build.sh`

**Problem:** Embedding `PRowl.entitlements` with ad-hoc `-` signing.

**Why forbidden:** Unresolved `$(AppIdentifierPrefix)` prevents launch.

**Correct approach:** Local builds = ad-hoc, no entitlements. Release builds = Xcode + team ID.

### 3. Detached settings window for normal configuration

**Problem:** Keyboard focus in popover is limited.

**Correct approach:** Keep settings **inline** in the popover (`PopoverUIState.showingSettings`). Use `openSettingsInPopover()` only when opening from a notification tap.

### 4. Deprecated notification APIs

Use **`UNUserNotificationCenter`** only.

### 5. `--deep` codesign as a substitute for proper release signing

Acceptable for local ad-hoc smoke tests. **App Store artifacts** must come from Xcode archive/export, not manual deep signing hacks.

---

## Approved solutions to common problems

### “Popover needs keyboard focus”

Token fields live inline in the popover settings screen. Do not reclass the popover window. If typing is awkward, that is an NSPopover platform limitation — not a reason to add hacks or a detached window unless the user explicitly asks.

### “Notifications don’t work in local build”

1. App must run as **`PRowl.app`** bundle (not bare `swift run` executable).
2. Must be **code signed** (`./build.sh` does ad-hoc sign).
3. On **macOS 26+**, permission must be requested from an **explicit user action** (Settings → **Enable Notifications**). Do not auto-prompt on launch — macOS rejects or errors those requests.
4. After granting, the app registers with Notification Center by delivering a first notification (`registerWithNotificationCenter()`).
5. User must **grant permission** (System Settings → Notifications → PRowl). `tccutil reset` fails if permission was never requested — that is normal.
6. For stable TCC during dev, copy to **`/Applications/PRowl.app`** and run from there.
7. **`NotificationManager.bindDelegate()`** must run after SwiftUI activation.

### “Icon white border in Finder”

Finder adds a white mat to PNGs with an **alpha channel**, even if pixels look opaque. The pipeline must export **RGB-only** (no alpha):

```bash
swift tools/transparent_corners.swift Resources/AppIcon-source.png Resources/AppIcon-rounded.png 40
swift tools/flatten_icon_canvas.swift Resources/AppIcon-rounded.png Resources/AppIcon.png 1024 0.96
./build.sh   # uses tools/make_icns.swift, not sips, for .icns
```

After rebuilding, clear Finder icon cache if needed: `touch /Applications/PRowl.app` or restart Finder.

### “New Swift file added”

1. File under `Sources/PRowl/`
2. `./scripts/generate-xcodeproj.sh` if release/Xcode needs it
3. `swift build` or `./build.sh`

---

## Code style

- **`final class`** for controllers/managers; **`enum`** for stateless utilities (`KeychainStore`, `AppCoordinator`).
- Small focused types in **`Services/`**, SwiftUI in **`Views/`**.
- Comments only for non-obvious business rules (polling diff logic, Keychain sandbox behavior).
- Prefer existing **`GlassSupport`** modifiers (`.prowlGlassPanel()`, `.prowlScrollStyle()`, etc.) for UI consistency.
- Availability checks for OS-version-specific UI; never assume macOS 26.

---

## Commands reference

```bash
./build.sh              # Local dev bundle (ad-hoc signed)
./build.sh debug        # Debug configuration
./dmg.sh                # Personal install DMG
DEVELOPMENT_TEAM=XXX ./release.sh   # App Store archive
./scripts/generate-xcodeproj.sh     # Refresh Xcode project from project.yml
swift build             # Compile only (no .app bundle)
```

---

## Agent pre-merge checklist

Before finishing a task, confirm:

- [ ] No private APIs, swizzling, or runtime class hacks
- [ ] Release path (`project.yml` / entitlements) still valid
- [ ] Secrets only in Keychain
- [ ] New entitlements justified and minimal
- [ ] Popover still closes (transient behavior intact)
- [ ] Configuration that needs typing uses inline settings in the popover, not a detached window
- [ ] `swift build` succeeds
- [ ] If Swift sources changed, XcodeGen project regenerated when needed
- [ ] App Store–only behavior (sandbox keychain group) degrades gracefully in local ad-hoc builds
