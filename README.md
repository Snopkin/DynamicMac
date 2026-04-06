# DynamicMac

A menu-bar agent app that gives macOS its own Dynamic-Island-style overlay
around the notch. Move the cursor to the top of the screen and a rounded
pill springs open with glanceable widgets — timers, system-wide Now Playing
controls — then collapses when you move away. On Macs without a notch, a
simulated notch pill renders at the top-center of the active display.

No Dock icon. No windows until you need them. Designed to be
battery-friendly and stay out of the way until you look at it.

## Status

Pre-release. Phases 0–5 of the implementation plan are complete; the app is
being hardened for a first public build. See `TECHNICAL_PLAN.md` for the
full phased roadmap and decisions log.

## Requirements

- macOS 15.0 Sequoia or later
- Apple Silicon or Intel Mac (notched or not — both code paths ship)
- Xcode 26 and Swift 6 to build from source

## Features

- **Hover-triggered island** at the notch, with a native SwiftUI spring
  animation and a `matchedGeometryEffect` morph between collapsed and
  expanded shapes.
- **Timers widget** — start / pause / resume / cancel from the island;
  timers keep counting when the island collapses, persist across relaunch,
  and fire a `UserNotifications` notification plus a brief auto-expand on
  completion.
- **Now Playing widget** — reads system-wide media state (Music, Spotify,
  Safari / Chrome media sessions, Podcasts, VLC, …) via the
  [`ungive/mediaremote-adapter`](https://github.com/ungive/mediaremote-adapter)
  bridge, shows title / artist / album art, and sends play-pause / next /
  previous back to the source app.
- **Settings window** — launch-at-login, tint, widget ordering, per-widget
  toggles, About with attributions.
- **Accessibility** — labels and hints on every control, Dynamic Type
  clamped to a range that fits the fixed-height island, `Reduce Motion`
  swaps the spring for a short ease curve.
- **Low Power Mode aware** — animation downgrades when the system reports
  a reduced power state.
- **Sparkle updates** — menu bar → "Check for Updates…" once a public feed
  is wired (see "Sparkle" below).

## Build from source

```bash
git clone https://github.com/<user>/DynamicMac.git
cd DynamicMac
open DynamicMac.xcodeproj
```

Build the `DynamicMac` scheme for "My Mac". Swift Package Manager will
resolve `DynamicNotchKit` (MIT) and `Sparkle` (MIT) on first build.

The `mediaremote-adapter` Perl helper and its framework are vendored under
`DynamicMac/Resources/mediaremote-adapter/` and
`External/mediaremote-adapter/`; nothing extra to install.

### Regenerating the app icon

The icon is generated deterministically from a Swift script — no design
tool involved. Re-run after tweaking colors or proportions:

```bash
swift Scripts/generate_app_icon.swift
```

Output lands in `DynamicMac/Assets.xcassets/AppIcon.appiconset/`.

### Sparkle

The Sparkle updater ships enabled in the menu bar, but the feed URL and
EdDSA public key are placeholders for now
(`INFOPLIST_KEY_SUFeedURL`, `INFOPLIST_KEY_SUPublicEDKey`). Pre-public
release, generate a keypair with `sign_update` from the Sparkle tools,
host an appcast, and update both Info.plist keys (currently injected via
the app target's build settings).

## Third-party components

- [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) — MIT
  License. Pinned to 1.0.0. Handles the `NSPanel`, multi-display, and
  simulated-notch plumbing.
- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) —
  BSD-3-Clause License. Vendored Perl helper + `MediaRemoteAdapter.framework`
  bridging Apple's private `MediaRemote.framework` so the Now Playing
  widget works post-macOS-15.4 without SIP tweaks.
- [Sparkle](https://github.com/sparkle-project/Sparkle) — MIT License.
  Pinned to 2.9.1. Auto-updater.

Full license texts ship inside the app bundle and are visible from
Settings → About.

## License

DynamicMac itself is proprietary — the source in this repo is not open
source, and the binary is free for personal non-commercial use under the
terms of [`LICENSE`](LICENSE). The third-party components above keep their
original licenses.
