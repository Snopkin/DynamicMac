# DynamicMac — Phased Implementation Plan

Plan compiled 2026-04-05. Consumes two research briefs:
- Platform brief: `/Users/lidor.nirshalom/.claude/plans/graceful-whistling-wilkes-agent-a4a75c4d9233f2210.md` (notch APIs, NSPanel, hover, fullscreen, multi-display, entitlements, battery, SwiftUI/AppKit hybrid, animation, ~50 cited sources).
- Media brief: `/Users/lidor.nirshalom/.claude/plans/graceful-whistling-wilkes-agent-aaedcef8f4c50b19c.md` (MediaRemote locked down in macOS 15.4, `ungive/mediaremote-adapter` is the 2026 answer, integration sketch, signing checklist, competitor analysis).

## 1. Context

**DynamicMac** is a macOS menu-bar agent app that gives MacBooks a Dynamic-Island-style overlay around the notch. When the user moves the cursor to the notch, a rounded-rectangle island morphs open with a native spring animation and shows a small glanceable surface: timers, system-wide Now Playing controls, and lightweight status widgets. On Macs without a notch (external displays, older Macs), a simulated notch-pill renders at the top-center of the active screen. Agent-style (`LSUIElement`), no Dock icon, battery-friendly, distributed via Developer ID + notarization + Sparkle.

Phase end-state deliverables:
- **After Phase 0**: clean, buildable, launchable skeleton. No window, menu bar icon only, nothing visual at the notch yet. Template residue gone.
- **After Phase 1 (MVP)**: the overlay actually appears. Hover the notch, island springs open with a placeholder widget, collapses on exit. Works on notched and non-notched displays. Quit via menu bar.
- **After Phase 2**: working Timers widget inside the island with notifications on completion.
- **After Phase 3**: working Now Playing widget reading Music/Spotify/Safari/Podcasts/etc. with play-pause/skip controls.
- **After Phase 4**: Settings window (launch-at-login, appearance, widget toggles, About).
- **After Phase 5**: performance-tuned, accessibility-clean, notarized, shippable v1 artifact.

## 2. Locked-in decisions (reference table)

| # | Decision |
|---|---|
| 1 | Distribution: Developer ID Application + notarization + Sparkle. Not App Store. Sandbox OFF (needed to spawn `/usr/bin/perl`). |
| 2 | Minimum macOS: 15.0 Sequoia. Swift 6 with data-race safety. |
| 3 | UI: SwiftUI + AppDelegate bridge via `@NSApplicationDelegateAdaptor`. No SwiftData. No `NavigationSplitView`. |
| 4 | Notch plumbing: `MrKai77/DynamicNotchKit` (MIT), pinned to a specific tag. No forking or reimplementing. |
| 5 | No-notch behavior: simulated notch at top-center via DynamicNotchKit's built-in mode. |
| 6 | Hover: NSTrackingArea via DynamicNotchKit. No Accessibility, no polling, no global event monitors. |
| 7 | Animation v1: SwiftUI `.spring(response: 0.35, dampingFraction: 0.78)` + `matchedGeometryEffect`. Metal shaders deferred. |
| 8 | Media/Now Playing: `ungive/mediaremote-adapter` (BSD-3), bundled as a resource, spawned via `/usr/bin/perl`. Hidden behind a `MediaSource` protocol. |
| 9 | App style: `LSUIElement = true`. `NSStatusItem` menu bar icon for Quit/Settings/About. SwiftUI `Settings` scene. |
| 10 | State: `@Observable` macro, no Combine `@Published`, no Redux/TCA. |
| 11 | MVP scope: overlay + hover + spring + one placeholder widget. Everything else is phased. |
| 12 | Widget priority stack: Now Playing > Timers > Placeholder. Highest-priority widget with content wins. Matches iOS Dynamic Island. |
| 13 | Technical plan lives at repo root as `TECHNICAL_PLAN.md` — written in Phase 0, updated after each phase. |

## 3. High-level architecture

### 3.1 Module boundaries

```
DynamicMac/
├── App/
│   ├── DynamicMacApp.swift        // @main, @NSApplicationDelegateAdaptor, empty Settings scene
│   └── AppDelegate.swift          // lifecycle, NSStatusItem, owns NotchIslandController
├── Island/
│   ├── NotchIslandController.swift // owns DynamicNotch<IslandContentView>, hover-to-state translator
│   ├── IslandState.swift          // @Observable state machine (idle/hoverCollapsed/expanded)
│   ├── IslandContentView.swift    // SwiftUI root inside the island, matchedGeometryEffect
│   └── Constants.swift            // all tuning knobs (sizes, radii, durations)
├── Widgets/
│   ├── HelloWorldWidgetView.swift // Phase 1 placeholder
│   ├── TimerWidgetView.swift      // Phase 2
│   └── NowPlayingWidgetView.swift // Phase 3
├── Services/
│   ├── MediaSource.swift          // Phase 3 protocol
│   ├── MediaRemoteAdapterBridge.swift // Phase 3 concrete
│   ├── MediaService.swift         // Phase 3 @Observable wrapper
│   └── TimerService.swift         // Phase 2
├── Models/
│   ├── TimerModel.swift           // Phase 2
│   └── NowPlayingInfo.swift       // Phase 3
├── Settings/
│   ├── AppSettings.swift          // Phase 4 @Observable persisted singleton
│   ├── SettingsView.swift         // Phase 4 SwiftUI TabView
│   └── WidgetID.swift             // typed widget enum
├── Resources/
│   └── mediaremote-adapter/       // Phase 3 vendored Perl + framework + LICENSE
├── External/
│   └── mediaremote-adapter/       // Phase 3 source at pinned SHA + VENDORING.md
└── Assets.xcassets/               // already present
```

Test targets: `DynamicMacTests/` and `DynamicMacUITests/` stay in place, replaced with compiling tests in Phase 0 and grown per-phase.

### 3.2 Data flow

```
              ┌──────────────────────┐
              │ AppDelegate          │   owns everything AppKit
              │  • NSStatusItem      │
              │  • NotchIslandController ──┐
              └──────────────────────┘     │
                                           │ owns
                                           ▼
              ┌─────────────────────────────────────────┐
              │ NotchIslandController (@Observable)     │
              │  • DynamicNotch<IslandContentView>      │
              │  • IslandState                          │
              │  • service injections                   │
              └─────────────────────────────────────────┘
                         │ renders SwiftUI content
                         ▼
              ┌─────────────────────────────────────────┐
              │ IslandContentView                       │
              │  switch islandState.phase {             │
              │    case .idle:            thin shape    │
              │    case .hoverCollapsed:  glow          │
              │    case .expanded:        widgets       │
              │  }                                      │
              │  .matchedGeometryEffect + spring        │
              └─────────────────────────────────────────┘
                         │ reads
                         ▼
              ┌─────────────────────────────────────────┐
              │ Services (@Observable)                  │
              │  TimerService, MediaService, AppSettings│
              └─────────────────────────────────────────┘
```

### 3.3 State ownership

- **AppDelegate**: singleton lifetime, owns `NotchIslandController`, `NSStatusItem`, and all services. Tears down on `applicationWillTerminate`.
- **NotchIslandController**: owns the `DynamicNotch` instance, the `IslandState`, and injected service references. Lives as long as the app.
- **IslandState**: `@Observable` class with a `phase: Phase` enum plus derived properties (corner radius, frame). Single source of truth for visual state. Mutated by DynamicNotchKit hover callbacks.
- **Services** (`TimerService`, `MediaService`, `AppSettings`): `@Observable` classes created in `AppDelegate.applicationDidFinishLaunching` and injected into `NotchIslandController`. App-lifetime. Exposed to SwiftUI via direct property access, not `@Environment` — keeps the injection graph explicit.
- **SwiftUI views**: own no persistent state beyond local UI concerns (`@State` for transient). Everything that outlives a view transition lives in the services.
- **Concurrency**: everything UI-adjacent is MainActor by default (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is already set in the pbxproj). The media adapter subprocess and its pipe reads are the only non-main work; they hop back via `Task { @MainActor in ... }` for state updates.

## 4. Phased roadmap

### Phase 0 — Reset template and hygiene

**Goal**: clean buildable skeleton. App launches, registers as a background agent with a menu bar icon, nothing more. Zero SwiftData, zero NavigationSplitView, zero watchOS residue in bundle id.

**Files to modify**:
- `DynamicMac.xcodeproj/project.pbxproj` — minimal edits only:
  - `MACOSX_DEPLOYMENT_TARGET`: `26.4` → `15.0` (all configs and targets).
  - `PRODUCT_BUNDLE_IDENTIFIER`: `com.lidor.adonis.watchkitapp.DynamicMac` → `com.lidor.DynamicMac` (app target). Tests get `.Tests` and `.UITests` suffixes.
  - `SWIFT_VERSION`: `5.0` → `6.0` (all targets).
  - `ENABLE_APP_SANDBOX`: `YES` → `NO` (app target only).
  - Keep: `ENABLE_HARDENED_RUNTIME = YES`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `DEVELOPMENT_TEAM = 3VALUUA5CP`.
  - Add INFOPLIST_KEYs on the app target: `INFOPLIST_KEY_LSUIElement = YES`, `INFOPLIST_KEY_CFBundleDisplayName = "DynamicMac"`, `INFOPLIST_KEY_NSHumanReadableCopyright = "Copyright © 2026 Lidor Nir Shalom"`.
  - Drop: `REGISTER_APP_GROUPS`, `ENABLE_USER_SELECTED_FILES` — unused.
  - Note: the project uses `PBXFileSystemSynchronizedRootGroup`, so file adds/removes do not require further pbxproj edits. Create/delete files on disk under `DynamicMac/`.
- `DynamicMac/DynamicMacApp.swift` — rewrite. Under 25 lines. Contents: `import SwiftUI`, `@main struct DynamicMacApp: App`, `@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate`, body containing only `Settings { EmptyView() }`. No SwiftData.
- `DynamicMac/ContentView.swift` — **delete** (replaced by Island in Phase 1).
- `DynamicMac/Item.swift` — **delete**.
- `DynamicMac/Assets.xcassets/` — leave as-is. Placeholders stay empty until Phase 5.

**Files to create**:
- `DynamicMac/App/DynamicMacApp.swift` — move from repo root into `App/`.
- `DynamicMac/App/AppDelegate.swift` — minimal stub (~60 lines). `final class AppDelegate: NSObject, NSApplicationDelegate`. `applicationDidFinishLaunching` creates an `NSStatusItem.variableLength`, sets SF Symbol `oval.fill` as placeholder image, attaches a 3-item menu: "About DynamicMac" (disabled), "Settings…" (disabled), separator, "Quit DynamicMac" wired to `NSApp.terminate(nil)`.
- Placeholder directories with `.gitkeep`: `DynamicMac/Island/`, `DynamicMac/Widgets/`, `DynamicMac/Services/`, `DynamicMac/Models/`, `DynamicMac/Settings/`.
- `.gitignore` at repo root — standard Xcode: `.DS_Store`, `xcuserdata/`, `*.xcuserstate`, `DerivedData/`, `build/`, `.swiftpm/`, `.build/`. `Package.resolved` is committed starting Phase 1.
- `TECHNICAL_PLAN.md` at repo root — copy of this plan (the version in `.claude/plans/`). Serves as the working source-of-truth for future sessions. Update the "Status" line and phase-progress notes as phases complete.

**Tests (replace, don't extend)**:
- `DynamicMacTests/DynamicMacTests.swift` — replace the empty template with a compile-only smoke test (`@testable import DynamicMac`, single assertion). Swift Testing (`import Testing`) if Xcode 26 supports it under Swift 6; otherwise XCTest.
- `DynamicMacUITests/DynamicMacUITests.swift` — keep launch test, remove empty performance stub. Launch assertion: after `app.launch()`, `app.windows.firstMatch.exists` is false (LSUIElement).
- `DynamicMacUITests/DynamicMacUITestsLaunchTests.swift` — keep.

**Verification**:
1. `xcodebuild -project DynamicMac.xcodeproj -scheme DynamicMac -configuration Debug -destination 'platform=macOS' build` succeeds, zero Swift 6 data-race warnings.
2. Run the app. No Dock icon. Menu bar icon present. Clicking it shows the 3-item menu. Quit works.
3. `xcodebuild test` passes.
4. Activity Monitor: DynamicMac idle CPU < 1%.

**Out of scope**: DynamicNotchKit, any overlay, any hover, any widget content, any real tests beyond compile-smoke.

**Pre-phase questions**: confirm bundle id `com.lidor.DynamicMac`, app display name `DynamicMac`, status-bar icon preference.

---

### Phase 1 — MVP: overlay + hover + spring expand

**Goal**: the island appears. Hover expands it, exit collapses it, inside shows "Hello, DynamicMac" + today's date. Works on notched and non-notched displays.

**Dependency addition**:
- Add `MrKai77/DynamicNotchKit` via `File → Add Package Dependencies`, URL `https://github.com/MrKai77/DynamicNotchKit`. Pin to a specific released tag (implementer verifies latest stable with macOS 15 support at integration time). Commit `Package.resolved`.

**Files to create**:
- `DynamicMac/Island/Constants.swift` (~40 lines) — single source of truth for all tuning knobs. `enum Constants { enum Island { static let expandedWidth: CGFloat = 420; static let expandedHeight: CGFloat = 90; static let collapsedHeight: CGFloat = 32; static let expandedCornerRadius: CGFloat = 22; static let collapsedCornerRadius: CGFloat = 12 } enum Animation { static let spring: SwiftUI.Animation = .spring(response: 0.35, dampingFraction: 0.78, blendDuration: 0) } }`.
- `DynamicMac/Island/IslandState.swift` (~60 lines) — `@Observable final class IslandState`, `enum Phase: Equatable { case idle, hoverCollapsed, expanded }`, `var phase: Phase = .idle`, derived `cornerRadius`, `size`. Methods `onHoverEnter()`, `onHoverExit()`, `toggleExpanded()` wrap mutations in `withAnimation(Constants.Animation.spring)`.
- `DynamicMac/Island/IslandContentView.swift` (~100 lines) — `struct IslandContentView: View`, `@Bindable var state: IslandState`, `@Namespace private var islandNamespace`. Body switches on `state.phase`, renders `RoundedRectangle(cornerRadius: state.cornerRadius, style: .continuous).fill(.black)` with `.matchedGeometryEffect(id: "island", in: islandNamespace)`. Overlays `HelloWorldWidgetView()` in expanded branch. Single `.animation(Constants.Animation.spring, value: state.phase)`. Respects `@Environment(\.accessibilityReduceMotion)` — swap spring for `.easeInOut(duration: 0.15)` when on.
- `DynamicMac/Island/NotchIslandController.swift` (~120 lines) — `@Observable @MainActor final class NotchIslandController`. Holds `let state = IslandState()` and `private var notch: DynamicNotch<IslandContentView>?`. `init()` constructs `DynamicNotch` with a closure returning `IslandContentView(state: state)`. Exposes `func start()` (begin observing, wire package hover callbacks into `state.onHoverEnter()` / `.onHoverExit()`) and `func shutdown()`. Implementer skims DynamicNotchKit's README once at integration time for the exact API surface — look for universal / simulated mode flag, hover callbacks.
- `DynamicMac/Widgets/HelloWorldWidgetView.swift` (~30 lines) — centered `VStack` with "Hello, DynamicMac" and `Text(Date.now, style: .date)`. White foreground.

**Files to modify**:
- `DynamicMac/App/AppDelegate.swift` — add `private var islandController: NotchIslandController?`, instantiate in `applicationDidFinishLaunching`, call `.start()`, release in `applicationWillTerminate`.

**Tests**:
- `DynamicMacTests/IslandStateTests.swift` — state machine transitions. `@Test("hover enter transitions idle → expanded")`, `@Test("hover exit returns expanded → idle")`, `@Test("phase transitions are idempotent")`. Under 80 lines.

**Verification**:
1. Build clean, zero data-race warnings.
2. On a notched MacBook: launch, hover the notch, island springs open showing "Hello, DynamicMac" + today's date. Move cursor away, see it collapse. No focus steal — can keep typing in another app.
3. On external display (or simulated notch): pill appears at top-center, same hover behavior.
4. Switch Spaces while expanded — island remains visible.
5. Toggle Reduce Motion — animation degrades to ease curve.
6. Safari fullscreen → hover top → island appears above fullscreen content.
7. Activity Monitor: idle <2%, animation briefly spikes then returns to idle.
8. Quit via menu bar. Process exits.

**Out of scope**: timers, media, Settings panel (still disabled), persistence, app icon, keyboard shortcuts, haptics.

**Pre-phase questions**: DynamicNotchKit tag to pin; Mac model and macOS version for primary testing (notch height and Tahoe validation); OK to commit `Package.resolved`; any spring tuning deviation.

---

### Phase 2 — Timers widget

**Goal**: users can start, pause, resume, cancel timers from the expanded island. Timers keep running when the island collapses. On completion the island auto-expands briefly and a `UserNotifications` notification fires.

**Files to create**:
- `DynamicMac/Models/TimerModel.swift` (~80 lines) — `@Observable final class TimerModel: Identifiable, Codable`. Fields: `id`, `label`, `totalDuration`, `startedAt`, `pausedAt`, `state: TimerState` (`.stopped | .running | .paused | .completed`), computed `timeRemaining`. Codable for UserDefaults JSON blob persistence.
- `DynamicMac/Services/TimerService.swift` (~140 lines) — `@Observable @MainActor final class TimerService`. `var timers: [TimerModel]`. One shared `Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true)` with `timer.tolerance = 0.25` (battery-friendly per platform brief §8). Created only when ≥1 timer is running, invalidated at 0. Each tick recomputes `timeRemaining`, detects zero-crossings, marks completed, posts `UNUserNotification`, exposes `var lastCompletedID: UUID?` for controller observation. Persistence helpers `load()` / `save()` on mutate and `applicationWillTerminate`. First-launch notification permission deferred until first timer start (never on cold launch).

**Files to modify**:
- `DynamicMac/Widgets/TimerWidgetView.swift` — new file, ~150 lines (may approach 250-cap; split into subviews if it does). `@Bindable var service: TimerService`. List of active timers with `.monospacedDigit()`, play/pause/cancel controls, quick-picker (1/5/10/25 min + custom stepper). Completion bounce: `withAnimation(Constants.Animation.completionBounce)` on `scaleEffect(1.05)` then back.
- `DynamicMac/Island/NotchIslandController.swift` — accept injected `TimerService`, observe `service.lastCompletedID`, on change call new `func autoExpandBriefly(duration: TimeInterval = 3.0)` (state → expanded, then back to idle after duration unless cursor inside).
- `DynamicMac/Island/IslandContentView.swift` — expanded branch routes by the priority stack (Now Playing > Timers > Placeholder). In Phase 2 with no media service yet, effectively Timers > Placeholder.
- `DynamicMac/App/AppDelegate.swift` — instantiate `TimerService`, inject.
- `DynamicMac/Island/Constants.swift` — add `completionBounce` animation and `briefAutoExpandDuration = 3.0`.

**Tests**:
- `DynamicMacTests/TimerServiceTests.swift` (<200 lines) — state transitions, tick zero-crossing, persistence round-trip, "single shared ticker is created/torn down correctly" invariant. Inject a clock protocol so tests don't sleep. No UI tests this phase.

**Verification**:
1. Build clean.
2. Start a 10s timer. Countdown updates every second.
3. Collapse, wait, see notification at 0 and brief auto-expand.
4. Two simultaneous timers tick via one shared NSTimer.
5. Pause mid-run, wait 5s, resume — `timeRemaining` preserved.
6. Quit and relaunch — running timers behavior matches whatever the user chose in pre-phase (recommended: discard running, keep completed history for session).
7. Activity Monitor: idle <1% (no ticker), 3 running <2% (one tick/sec shared). Energy Impact "Low".

**Out of scope**: categories, recurring timers, Pomodoro presets, history beyond session, custom sounds, menu bar popover.

**Pre-phase questions**: relaunch behavior for running timers (discard / pause / resume, recommendation discard); notification permission timing (on first timer start recommended). Widget routing policy is locked in decision #12 — no question.

---

### Phase 3 — Now Playing widget

**Goal**: the expanded island shows what's playing system-wide (Music, Spotify, Safari/Chrome via MediaSession, Podcasts, VLC, etc.) with working play/pause, skip forward, skip back. Album art when available.

**Vendoring the adapter** (one-time, manual):
- Clone `ungive/mediaremote-adapter` at a specific SHA into `DynamicMac/External/mediaremote-adapter/` (committed).
- Build `MediaRemoteAdapter.framework` per upstream CMake.
- Copy built artifacts into `DynamicMac/Resources/mediaremote-adapter/`:
  - `mediaremote-adapter.pl`
  - `MediaRemoteAdapter.framework/` (full bundle)
  - `LICENSE` (BSD-3)
- Verify in Xcode Build Phases: framework is in **Copy Bundle Resources** (not linked — `dlopen`-loaded at runtime by Perl). File-system synchronized group may or may not route it to the right phase; add a file exception override if needed.
- Add a **Run Script** build phase after Copy Bundle Resources to re-sign the vendored framework for notarization: `codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$CODESIGNING_FOLDER_PATH/Contents/Resources/mediaremote-adapter/MediaRemoteAdapter.framework"`.
- Record the vendored SHA and CMake invocation in `DynamicMac/External/mediaremote-adapter/VENDORING.md`.

**Files to create**:
- `DynamicMac/Models/NowPlayingInfo.swift` (~40 lines) — value type. Fields: `bundleIdentifier`, `title`, `artist`, `album`, `artwork: Data?`, `duration`, `elapsedTime`, `isPlaying`, `timestamp`. `Equatable`. Matches the media brief's sketch.
- `DynamicMac/Services/MediaSource.swift` (~40 lines) — `@MainActor protocol MediaSource: AnyObject`. `var current: NowPlayingInfo? { get }`, `func start()`, `func stop()`, `func send(_ command: MediaCommand) async`. Protocol abstraction for swapping in an AppleScript fallback later.
- `DynamicMac/Services/MediaRemoteAdapterBridge.swift` (~200 lines, biggest file — flag for split in Phase 5). Concrete implementation from media brief §6. Responsibilities:
  - Locate `mediaremote-adapter.pl` and `MediaRemoteAdapter.framework` via `Bundle.main.url(forResource:withExtension:subdirectory:)`. Nil → un-runnable state, log and disable gracefully.
  - Spawn `/usr/bin/perl` via `Process` with `[scriptURL.path, frameworkURL.path, "stream"]`. Pipe stdout and stderr.
  - `readabilityHandler` reads chunks, splits on `\n`, parses JSON, maps `payload` dict into `NowPlayingInfo`, hops to main via `Task { @MainActor in ... }`.
  - `send(_ command:)` spawns a short-lived `perl ... send <command>` subprocess and awaits termination.
  - `terminationHandler` triggers debounced restart (1s delay, exponential backoff capped at 30s). After 3 rapid failures, surface a `status: Status` = `.unavailable` to UI.
  - `stop()`: clear handlers, terminate, nil out.
  - Defensive `as?` casts throughout — media brief notes adapter key names may drift across versions.
- `DynamicMac/Services/MediaService.swift` (~80 lines) — `@Observable @MainActor final class MediaService`. Owns one `MediaSource` (initially always the adapter bridge). Republishes `var current: NowPlayingInfo?`. Exposes `togglePlayPause() async`, `next() async`, `previous() async`. Optionally subscribes to `DistributedNotificationCenter` for `com.apple.Music.playerInfo`, `com.apple.iTunes.playerInfo`, `com.spotify.client.PlaybackStateChanged` as fast-edge signals. Gate behind a feature flag if Phase 3 slips.
- `DynamicMac/Widgets/NowPlayingWidgetView.swift` (~150 lines) — `@Bindable var service: MediaService`. Left = album art (`Image(nsImage: NSImage(data: artworkData))` with SF Symbol fallback). Middle = marquee title + static artist. Right = three SF Symbol buttons (`backward.fill`, `play.fill`/`pause.fill`, `forward.fill`). Reads `current` (`@Observable`) so SwiftUI reflows on track change. `withAnimation(Constants.Animation.mediaCrossfade)` on artwork change. Full accessibility labels.

**Files to modify**:
- `DynamicMac/App/AppDelegate.swift` — instantiate `MediaService`, call `.start()`, inject into `NotchIslandController`.
- `DynamicMac/Island/NotchIslandController.swift` — accept injected `MediaService`.
- `DynamicMac/Island/IslandContentView.swift` — expanded branch routes by the locked priority stack (Now Playing > Timers > Placeholder). Implement as a computed `var activeWidget: WidgetKind` on the view/state, driven by `MediaService.current?.isPlaying` and `TimerService.hasRunningTimer`.
- `DynamicMac.xcodeproj/project.pbxproj` — Run Script build phase for vendored framework codesigning. Real pbxproj edit, not synchronized-group-managed.

**Tests**:
- `DynamicMacTests/MediaRemoteAdapterBridgeTests.swift` (<200 lines) — JSON parser with canned inputs (playing/paused/stopped, with/without artwork, missing keys). Does not spawn Perl (integration).
- `DynamicMacTests/MediaServiceTests.swift` — fake `MediaSource` republishing through service. Protocol-backed test double.
- Manual integration test documented, not automated: spawn adapter, play Music.app, verify `current` populates <2s.

**Verification**:
1. Build. `codesign --verify --deep --strict --verbose=2 DynamicMac.app` passes.
2. Play in Music.app. Hover. Title/artist/art appear.
3. Click play/pause in island → Music.app responds.
4. Switch to Spotify, play different track. Island updates within ~1s.
5. YouTube in Safari — island picks it up via MediaSession.
6. Kill Perl subprocess from Activity Monitor → bridge auto-restarts within 2s.
7. Rename bundled script to simulate failure → graceful degradation, no crash, `.unavailable` state.
8. Quit app → Perl subprocess also terminates (no orphans).

**Out of scope**: lyrics, scrubbing, likes/favorites, multi-device control, Podcasts chapters, AirPlay target selection.

**Pre-phase questions**: vendoring strategy (submodule vs copy-in, recommendation copy-in); OK to bundle Perl helper and rely on `/usr/bin/perl` absolute path; DistributedNotificationCenter fast-edge subscriptions in Phase 3 or defer. Widget routing policy is locked in decision #12 — no question.

---

### Phase 4 — Settings and polish

**Goal**: Settings window from menu bar with meaningful toggles. Launch at login wired up. About section crediting dependencies.

**Files to create**:
- `DynamicMac/Settings/AppSettings.swift` (~100 lines) — `@Observable @MainActor final class AppSettings`. Backed by `UserDefaults.standard`. Keys as named constants. Fields: `launchAtLogin: Bool`, `showIdlePill: Bool`, `islandTintColor: Color` (hex-serialized), `widgetOrder: [WidgetID]`, `widgetEnabled: [WidgetID: Bool]`, `mediaFallbackEnabled: Bool`, `reduceBattery: Bool`. `launchAtLogin`'s setter calls `SMAppService.mainApp.register()` / `.unregister()` with rollback on failure.
- `DynamicMac/Settings/SettingsView.swift` (~200 lines, split into per-tab subviews if approaching 250-cap) — `TabView` tabs: General, Appearance, Widgets, Media, About.
  - **General**: launch at login toggle; hide idle pill toggle; cmd-Q quits toggle.
  - **Appearance**: tint color picker; collapsed width slider; respect Reduce Motion toggle (read-only if system Reduce Motion is on).
  - **Widgets**: checkbox list + drag reorder via `.onMove`.
  - **Media**: enable system Now Playing toggle; Test Connection button calling `mediaService.testConnection()`; fallback dropdown.
  - **About**: name, version, build (from `Bundle.main.infoDictionary`), GitHub link via `NSWorkspace.shared.open`, DynamicNotchKit (MIT) + mediaremote-adapter (BSD-3) attribution. License texts inline or disclosure.
- `DynamicMac/Settings/WidgetID.swift` (~20 lines) — typed enum.

**Files to modify**:
- `DynamicMac/App/DynamicMacApp.swift` — replace `Settings { EmptyView() }` with `Settings { SettingsView(settings: appDelegate.appSettings) }`.
- `DynamicMac/App/AppDelegate.swift` — instantiate `AppSettings`, enable Settings… menu item, wire via `NSApp.sendAction(Selector("showSettingsWindow:"), to: nil, from: nil)` (verify symbol for Sequoia at implementation time).
- `DynamicMac/Island/NotchIslandController.swift` — read `AppSettings` for tint, collapsed width so changes apply without restart.
- `DynamicMac/Widgets/*` — respect `AppSettings.widgetEnabled`.

**Tests**:
- `DynamicMacTests/AppSettingsTests.swift` (<120 lines) — round-trip persistence, launch-at-login register/unregister mock, widget order mutation.

**Verification**:
1. Build clean.
2. Menu bar → Settings… → window opens.
3. Toggle Launch at Login, quit, log out/in — app auto-launches.
4. Toggle widgets — island content updates without relaunch.
5. Pick new tint color — island body reflects on next hover.
6. Test Connection accurate.
7. About tab shows version + attributions.

**Out of scope**: iCloud sync, import/export, themes beyond single color, custom hotkeys, onboarding.

**Pre-phase questions**: launch-at-login default (recommendation: off); single tint vs theme system (recommendation: single color v1); which settings window plumbing (new `@Environment(\.dismissWindow)` or AppKit).

---

### Phase 5 — Polish, performance, and ship

**Goal**: shippable v1 artifact. Notarized, signed, battery-friendly, accessible, tested on notched + non-notched and macOS 15 + 26.

**Code review pass**:
- Walk every file. Flag >250 lines, functions >50 lines. Candidates: `MediaRemoteAdapterBridge.swift` (~200), `NowPlayingWidgetView.swift` (~150), `SettingsView.swift` (split proactively into per-tab files). Extract helpers or subviews. Document files that must stay long and why.
- DRY: consolidate stray constants into `Constants.swift`.
- Immutability: prefer `let` over `var`.
- No magic values: stray `0.35`, `420`, `10.0` → `Constants`.
- Self-documenting names: rename `x`, `tmp`, `data1`.

**Performance**:
- Activity Monitor idle CPU target <1%, wakeups/sec <5 idle.
- Expanded + animating CPU target <5%, back to idle within 100ms of animation end.
- Instruments Time Profiler on hover expand/collapse. Main-thread functions >2ms are a smell.
- Instruments Allocations over 10-minute run with media + timer. Check retain cycles in bridge `readabilityHandler` (must `[weak self]`).

**Low Power Mode**:
- Observe `ProcessInfo.isLowPowerModeEnabled` via `NSProcessInfoPowerStateDidChange`.
- When on: downgrade animation to ease curve, switch media to DistributedNotification-only mode (skip always-on Perl), skip non-essential timer ticks.
- Restore on exit.

**Accessibility**:
- Every interactive element has `.accessibilityLabel`, `.accessibilityHint`, `.accessibilityValue`.
- VoiceOver end-to-end test: every control reachable and announced.
- `@Environment(\.accessibilityReduceMotion)` — already wired in Phase 1. Extend to all widget-level animations.
- Dynamic Type clamp to `.medium`/`.large` and truncate gracefully (island has fixed height).

**Fullscreen game compatibility**:
- Test AppKit fullscreen (Safari green button) — island works.
- Test exclusive-fullscreen game (any modern Steam title) — island may be hidden (known macOS limitation per platform brief). Record observed behavior.

**Sparkle** (optional v1, strongly recommended pre-public-release):
- Add Sparkle SPM package. Generate EdDSA keypair. Public key in Info.plist, private key outside repo. `SUFeedURL` points to hosted feed. Wire "Check for Updates…" menu item to `SPUStandardUpdaterController`. Test with local feed.

**Notarization**:
- Archive in Xcode. `codesign --verify --deep --strict --verbose=2` passes.
- `xcrun notarytool submit ... --wait`.
- `xcrun stapler staple DynamicMac.app`.
- DMG via `create-dmg` or ZIP.
- Clean user account test: Gatekeeper allows without warning.

**README at repo root** (propose, ask before writing):
- One-paragraph description, screenshot, system requirements (macOS 15+), build-from-source, third-party notices (DynamicNotchKit MIT, mediaremote-adapter BSD-3), license (user picks).

**Verification — full end-to-end (DoD)**:
1. Fresh clone. Open in Xcode. Build Debug. Zero warnings on Swift 6 strict concurrency.
2. `xcodebuild test`. All green.
3. Archive → Distribute → Developer ID → notarize → staple. `spctl -a -v` reports notarized.
4. /Applications on clean account. No Gatekeeper dialog.
5. Menu bar icon present, no Dock icon.
6. Hover notch → island springs open (~350ms) showing active widget.
7. Cursor away → collapses smoothly.
8. Menu bar → Settings… opens.
9. Launch at Login → log out/in → app running.
10. Toggle Now Playing off → hover → no longer appears.
11. Start 10s timer → collapse → notification + brief auto-expand at 0.
12. Music → hover → track info + controls work.
13. Reduce Motion on → hover → ease instead of spring.
14. External display → simulated notch or pinned (per setting).
15. Safari fullscreen → hover → island above fullscreen.
16. Activity Monitor: idle <1%, animating <5%, Energy "Low".
17. Quit → no orphan Perl.
18. VoiceOver: every control announced.

Any failure is a release blocker.

**Out of scope**: localizations beyond English, analytics, crash reporting, onboarding flow, website, app icon design (placeholder acceptable, flag it).

**Pre-phase questions**: Sparkle in v1 or v1.0.1; app icon before v1 or placeholder; project license; OK to write README.md.

## 5. Critical files to create or modify

Flat list, paths relative to repo root. Each line is the purpose in one sentence.

- `DynamicMac.xcodeproj/project.pbxproj` — build settings (deployment target, bundle ID, sandbox off, Swift 6, LSUIElement, Phase 3 Run Script for vendored framework codesigning).
- `.gitignore` — standard Xcode exclusions, committed in Phase 0.
- `DynamicMac/App/DynamicMacApp.swift` — `@main`, adapts to AppDelegate, minimal Settings scene host.
- `DynamicMac/App/AppDelegate.swift` — lifecycle, owns `NSStatusItem`, `NotchIslandController`, services.
- `DynamicMac/Island/NotchIslandController.swift` — owns `DynamicNotch<IslandContentView>`, wires hover to `IslandState`, service injection.
- `DynamicMac/Island/IslandState.swift` — `@Observable` state machine.
- `DynamicMac/Island/IslandContentView.swift` — SwiftUI root inside the island, spring + `matchedGeometryEffect`, widget router.
- `DynamicMac/Island/Constants.swift` — all tuning knobs (sizes, radii, animation parameters, durations).
- `DynamicMac/Widgets/HelloWorldWidgetView.swift` — Phase 1 placeholder.
- `DynamicMac/Widgets/TimerWidgetView.swift` — Phase 2 UI.
- `DynamicMac/Widgets/NowPlayingWidgetView.swift` — Phase 3 UI.
- `DynamicMac/Models/TimerModel.swift` — `@Observable`, Codable, timer state.
- `DynamicMac/Models/NowPlayingInfo.swift` — value type for current track.
- `DynamicMac/Services/TimerService.swift` — single shared ticker, persistence, notifications.
- `DynamicMac/Services/MediaSource.swift` — protocol abstraction.
- `DynamicMac/Services/MediaRemoteAdapterBridge.swift` — concrete Perl subprocess bridge with auto-restart.
- `DynamicMac/Services/MediaService.swift` — `@Observable` façade over `MediaSource`.
- `DynamicMac/Settings/AppSettings.swift` — `@Observable` persisted singleton, launch-at-login wiring.
- `DynamicMac/Settings/SettingsView.swift` — `TabView` (General, Appearance, Widgets, Media, About).
- `DynamicMac/Settings/WidgetID.swift` — typed widget enum.
- `DynamicMac/Resources/mediaremote-adapter/` — vendored Perl script, framework bundle, LICENSE (Phase 3).
- `DynamicMac/External/mediaremote-adapter/` — source at pinned SHA + `VENDORING.md` (Phase 3).
- `DynamicMacTests/IslandStateTests.swift` — state machine tests (Phase 1).
- `DynamicMacTests/TimerServiceTests.swift` — tick, persistence (Phase 2).
- `DynamicMacTests/MediaRemoteAdapterBridgeTests.swift` — JSON parser tests (Phase 3).
- `DynamicMacTests/MediaServiceTests.swift` — protocol double tests (Phase 3).
- `DynamicMacTests/AppSettingsTests.swift` — persistence round-trip (Phase 4).
- `README.md` — repo root, Phase 5, ask first.
- `DynamicMac/ContentView.swift` — **delete** in Phase 0.
- `DynamicMac/Item.swift` — **delete** in Phase 0.
- `TECHNICAL_PLAN.md` — repo root, written in Phase 0 (copy of this plan). Updated after each phase completes.

## 6. Risks and open questions

- **macOS 26 (Tahoe) compatibility**. Tahoe introduced Liquid Glass and changed menu bar rendering. Platform brief flags this. If development machine is on 26.x, validate the full Phase 1 flow on Tahoe before declaring MVP done. DynamicNotchKit may not have a Tahoe release yet — file upstream or patch locally. **Open question**: which macOS is the dev machine running? Must answer before Phase 1.
- **DynamicNotchKit macOS 15/26 status**. Tag pinning requires checking release notes for Sequoia support. Research brief confirmed macOS 13+ historically. Implementer verifies at dependency-add.
- **mediaremote-adapter JSON envelope drift**. Adapter README warns key names may change. Pin SHA, re-verify parser at Phase 3 integration, defensive `as?` casts so key rename degrades instead of crashes.
- **Apple closing `com.apple.perl` whitelist**. If Apple restricts which Apple-signed binaries can load helper frameworks, the approach dies ecosystem-wide. Mitigation: `MediaSource` protocol lets us swap in an AppleScript fallback (40% coverage — Music and Spotify only per media brief). Fallback in code from Phase 3 even if dormant.
- **Sandbox-off + hardened runtime interaction**. Media brief: do not add `com.apple.security.cs.allow-unsigned-executable-memory` or `.cs.disable-library-validation` unless notarization requires them. Start minimal, add only on failure.
- **Timer tolerance vs precision**. `Timer.tolerance = 0.25` trades precision for battery. Short timers may drift visibly. Consider per-timer tolerance (lower for sub-minute) or a shorter tick at the cost of wakeups. **Open question**: acceptable tolerance?
- **Focus steal regression**. DynamicNotchKit should handle `.nonactivatingPanel` correctly. Verify expanding the island never pulls focus from the foreground app. Add to Phase 1 verification checklist permanently.
- **File length**. `MediaRemoteAdapterBridge.swift` most likely to hit 250 limit. Plan to split into `+Process`, `+Parsing` extensions. Flag during Phase 5.
- **Open question: dev Mac model**. Affects notch-height testing, fullscreen game test viability, ProMotion vs 60Hz tuning.
- **Open question: app icon**. No asset present. Ship v1 with SF Symbol placeholder or commission one?
- **Open question: license**. Global CLAUDE.md doesn't specify. Needed for README + About in Phase 5.

## 7. Verification / definition of done

End-to-end test procedure is documented inside Phase 5 "Verification — full end-to-end (DoD)" above, items 1–18. Each prior phase has its own phase-local verification (see Section 4). Any failure in 1–18 of Phase 5 is a release blocker.

## 8. Rejected alternatives

- **Mac App Store distribution** — impossible. Full Now Playing requires either linking MediaRemote (private, §2.5.1) or spawning Perl (§2.4.5(iii) bans downloading/installing executable code). Every shipping competitor distributes outside the store for this exact reason.
- **From-scratch notch plumbing** — unnecessary reinvention. DynamicNotchKit (MIT) encapsulates NSPanel, hover, multi-display, simulated notch. Building our own buys months of edge-case debugging.
- **Metal shader metaball animation in v1** — platform brief confirms SwiftUI spring + `matchedGeometryEffect` delivers production Dynamic-Island feel (BoringNotch does this). Shaders are a v2 luxury.
- **SwiftData persistence** — overkill for timers + settings. `UserDefaults` + `Codable` is simpler, no migration costs. Ripped out in Phase 0.
- **Combine `@Published`** — superseded by `@Observable` macro on macOS 14+. Better dependency tracking with less ceremony.
- **Polling for cursor position** — Apple's Energy Efficiency Guide explicitly calls it a battery anti-pattern. NSTrackingArea (via DynamicNotchKit) is event-driven.
- **MediaRemoteWizard / SIP-disable** — unshippable to end users.

## 9. Pre-phase questions for the user

Ask before starting each phase. All phases honor "minimal edits only" — do not expand scope mid-phase without another approval.

**Phase 0**:
- Confirm bundle id `com.lidor.DynamicMac`?
- Confirm display name `DynamicMac`?
- Confirm placeholder menu bar icon (SF Symbol `oval.fill` or other)?
- OK to delete `Item.swift` and `ContentView.swift`?

**Phase 1**:
- Which DynamicNotchKit tag to pin (latest stable on 2026-04-05)?
- Which Mac model + macOS version for primary testing?
- OK to commit `Package.resolved`?
- Any spring tuning deviation from `response: 0.35, dampingFraction: 0.78`?

**Phase 2**:
- Running timers on relaunch: discard / pause / resume?
- Permission prompt on first timer start (recommended) or on launch?

**Phase 3**:
- Vendoring strategy: submodule or copy-in (recommendation copy-in)?
- OK to bundle Perl helper at `/usr/bin/perl` absolute path?
- DistributedNotificationCenter fast-edge in Phase 3 or defer?

**Phase 4**:
- Launch at Login default (recommendation: off)?
- Hotkey support in v1 (recommendation: no)?
- Single tint color or full theme system (recommendation: single v1)?

**Phase 5**:
- Sparkle in v1 or v1.0.1?
- App icon commissioned or placeholder?
- Project license (MIT / Apache-2 / BSD-3 / proprietary)?
- OK to write `README.md` at repo root?
