# HighlightBar

A macOS click-through highlight bar that follows the mouse and stays on top of all windows.

## Run

```bash
cd HighlightBar
swift run
```

You should see a translucent bar that follows the cursor across screens.
Use the menu bar item (`HB`) to configure it or quit.

## Build .app

Create a double-clickable app bundle:

```bash
cd HighlightBar
./scripts/build-app.sh
```

This generates:

- `dist/HighlightBar.app`

The script embeds `Sparkle.framework`, writes the update keys into `Info.plist`,
and signs the bundle (ad-hoc locally; Developer ID + Hardened Runtime in CI when
`CODESIGN_IDENTITY` is set). For signed, notarized release builds and the update
appcast, see [`RELEASE.md`](../RELEASE.md).

Open it:

```bash
open "dist/HighlightBar.app"
```

## Menu Controls

- Height slider: set a font-size reference in points (`pt`) with `-` and `+` buttons.
  The app maps it to bar height with `height = 2 x font-size`.
- Transparency slider: adjust fill alpha from `10%` to `90%` with `-` and `+` buttons.
- Color circles: choose color directly in the main dropdown. Hover previews the color before you click.
- Show/Hide: toggle the whole highlighter (bar + any overlay) with the global `⌘ + Shift + H` shortcut or the `Hide Highlighter` / `Show Highlighter` menu item.
- Lock/Unlock: freeze the bar at its current spot with `⌘ + Shift + L` (or `Lock Bar Position`) so it stops following the mouse. While locked, nudge it with `⌘ + Shift + ↑` / `⌘ + Shift + ↓`. The `Keyboard Shortcuts` submenu lists them all.
- Mode: `Mode` submenu picks `Off` / `Bar only` / `Bar + spotlight` / `Screen tint`. Spotlight dims everything except a clear slot at the bar (follows the cursor); screen tint is a uniform colored wash. Overlay color and opacity are adjustable there and cover every display, staying fully click-through.
- Shape / Orientation: `Shape` switches between a thick `Ruler (band)` and a thin `Line`; `Orientation` switches between a horizontal band and a vertical column that follows the cursor's X.
- Tracking: `Tracking` drives the bar by `Mouse` (default, no permission), `Scroll wheel` (no permission), or `Keyboard (arrows)` (opt-in; needs Input Monitoring, falls back to Mouse).
- Profiles: `Profiles` applies a full settings bundle in one tap — built-ins `Dyslexia`, `ADHD / Focus`, `Low vision`, plus `Save Current as…` / `Delete Saved Profile` for your own.
- Launch at Login: toggle to start Highlight Bar automatically at login (via `SMAppService`).
- Welcome / Updates: `Show Welcome…` re-opens the first-run guide; `Check for Updates…` is an opt-in Sparkle check (no automatic background checks).
- Settings persistence: size reference, transparency, color, lock state/position, mode, per-mode overlay color/opacity, shape, orientation, tracking source, saved profiles, last-applied profile, and the launch-at-login / onboarding flags are remembered and restored on next launch.

## Multi-monitor

The bar follows the cursor onto whichever display it is on, sized in points so it
renders at the same physical size on Retina and non-Retina screens. When displays
change at runtime (resolution change, monitor plugged/unplugged) the bar
re-clamps so it is never stranded off-screen.

## Code

The app is a single SPM target split into focused files in
`Sources/HighlightBar/`:

- `main.swift` — entry point and the `HighlightBarApp` coordinator (status-bar
  menu, settings wiring, cursor tracking, global hotkey).
- `Settings.swift` — the `Settings` model plus `SettingsStore`, which persists to
  `UserDefaults` as JSON and migrates the older flat keys.
- `BarGeometry.swift` — pure, side-effect-free geometry for placing/clamping the
  bar on a screen (reused by later overlay work).
- `OverlayWindowManager.swift` — the shared always-on-top, click-through window
  factory and live display-change handling.
- `HighlightBarView.swift` / `ColorPickerMenuView.swift` — the bar view and the
  in-menu color picker.
