# Highlight Bar User Guide

This guide is for friends using the app on macOS or Windows.

## What It Does

Highlight Bar shows a translucent reading bar that follows your mouse and helps you track lines of text.

You can change:

- bar height
- transparency
- color

Your last-used settings are saved automatically.

## Downloads

- Latest release page: `https://github.com/25mattm/Highlighter/releases/latest`
- macOS file: `HighlightBar-macos.zip`
- Windows file: `HighlightBar-windows-x64.zip`

## Install On macOS

1. Download `HighlightBar-macos.zip`.
2. Unzip it.
3. Drag `HighlightBar.app` into `Applications`.
4. Open `HighlightBar.app`.

If macOS blocks opening:

1. Go to `System Settings -> Privacy & Security`.
2. Click `Open Anyway` for Highlight Bar.
3. Open the app again.

## Install On Windows

1. Download `HighlightBar-windows-x64.zip`.
2. Unzip it.
3. Run `HighlightBar.Windows.exe`.

If SmartScreen warns:

1. Click `More info`.
2. Click `Run anyway`.

## How To Use

1. Launch the app.
2. Find the app icon:
- macOS: `HB` in the menu bar.
- Windows: tray icon near the clock.
3. Open the menu to adjust:
- height (font-size reference)
- transparency
- color
4. Show or hide the bar at any time:
- Press `Ctrl + Shift + H` (Windows) or `⌘ + Shift + H` (macOS).
- Or use `Hide Bar` / `Show Bar` in the menu.
5. Lock the bar in place (macOS):
- Press `⌘ + Shift + L` (or `Lock Bar Position` in the menu) to freeze the bar where it is so it stops following the mouse. Press again to unlock.
- While locked, nudge it up or down with `⌘ + Shift + ↑` / `⌘ + Shift + ↓`.
- The lock state and locked position are remembered for next launch.
- The macOS menu lists every shortcut under `Keyboard Shortcuts`.
6. Quit from the same menu:
- macOS: `Quit Highlight Bar`
- Windows: `Quit Highlight Bar`

## Display Modes (macOS)

Open the menu-bar `HB` menu and choose `Mode`:

- **Off** — nothing is shown.
- **Bar only** — just the reading bar (the default).
- **Bar + spotlight** — dims the whole screen except a clear slot at the bar,
  which follows your cursor. Good for cutting visual clutter and focusing on one
  line at a time.
- **Screen tint** — a uniform colored wash over everything, for visual-stress
  relief.

Under `Mode` you can also set the overlay's **color** and **opacity** (remembered
separately for the spotlight and the tint). Overlays cover every display and stay
fully click-through, so you can keep working underneath them. `⌘ + Shift + H`
hides or shows the whole highlighter — bar and overlay together.

## Shape, Orientation & Tracking (macOS)

From the `HB` menu:

- **Shape** — `Ruler (band)` is the thick reading band; `Line (thin)` is a slim
  guide line.
- **Orientation** — `Horizontal` follows the cursor up and down; `Vertical
  (column)` is a full-height column that follows the cursor left and right.
- **Tracking** — what moves the bar:
  - `Mouse` (default) — follows the cursor. No permission needed.
  - `Scroll wheel` — the bar moves as you scroll. No permission needed.
  - `Keyboard (arrows)` — arrow keys move the bar. This needs macOS **Input
    Monitoring** permission; Highlight Bar asks for it and stays on Mouse until
    you grant access.

## Profiles (macOS)

`HB` menu → `Profiles` applies a whole bundle of settings in one tap:

- Built-ins: **Dyslexia**, **ADHD / Focus**, **Low vision** — sensible starting
  points you can tweak afterwards.
- **Save Current as…** stores your current setup as a named profile.
- **Delete Saved Profile** removes one of your saved profiles.

Your saved profiles and the last-applied profile are remembered.

## Launch at Login, Welcome & Updates (macOS)

From the `HB` menu:

- **Launch at Login** — toggle to have Highlight Bar start automatically when you
  log in.
- **Show Welcome…** — re-open the first-run welcome with the shortcut tips.
- **Check for Updates…** — check for a newer version. Updates are opt-in: the app
  never checks on its own and makes no network request unless you choose this.

## Update To A New Version

- macOS: choose `Check for Updates…` in the `HB` menu (in a released build), or
  download the latest zip from the releases page and replace the app.
- Windows: download the latest zip and replace the app.

## Uninstall

### macOS

1. Quit the app from the menu bar.
2. Delete `HighlightBar.app` from `Applications`.

### Windows

1. Quit the app from the system tray menu.
2. Delete the extracted app folder.

## Troubleshooting

### I do not see the icon

- macOS: check top-right menu bar for `HB`.
- Windows: expand the hidden tray icons near the clock.

### The app closes right away

- Re-open it from Applications (macOS) or the `.exe` folder (Windows).
- Make sure security prompts were accepted.

### Settings did not save

- Quit normally from the app menu, then relaunch.
- On Windows, ensure the app folder and `%APPDATA%` are writable.

### The bar is not visible

- Increase opacity in the menu.
- Change to a brighter color.
- Increase height.

## Privacy

Highlight Bar is a local utility app. It does not require sign-in and does not upload your files/content for normal use.
