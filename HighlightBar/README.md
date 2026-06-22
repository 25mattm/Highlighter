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

Open it:

```bash
open "dist/HighlightBar.app"
```

## Menu Controls

- Height slider: set a font-size reference in points (`pt`) with `-` and `+` buttons.
  The app maps it to bar height with `height = 2 x font-size`.
- Transparency slider: adjust fill alpha from `10%` to `90%` with `-` and `+` buttons.
- Color circles: choose color directly in the main dropdown. Hover previews the color before you click.
- Show/Hide: toggle the bar with the global `⌘ + Shift + H` shortcut or the `Hide Bar` / `Show Bar` menu item.
- Settings persistence: height reference, transparency, and color are remembered and restored on next launch.

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
