# HighlightBar

A macOS click-through highlight bar that follows the mouse and stays on top of all windows.

## Run

```bash
cd /Users/matthewmullett/Documents/New\ project/HighlightBar
swift run
```

You should see a translucent bar that follows the cursor across screens.
Use the menu bar item (`HB`) to configure it or quit.

## Build .app

Create a double-clickable app bundle:

```bash
cd /Users/matthewmullett/Documents/New\ project/HighlightBar
./scripts/build-app.sh
```

This generates:

- `dist/HighlightBar.app`

Open it:

```bash
open "/Users/matthewmullett/Documents/New project/HighlightBar/dist/HighlightBar.app"
```

## Menu Controls

- Height slider: set a font-size reference in points (`pt`) with `-` and `+` buttons.
  The app maps it to bar height with `height = 2 x font-size`.
- Transparency slider: adjust fill alpha from `10%` to `90%` with `-` and `+` buttons.
- Color circles: choose color directly in the main dropdown. Hover previews the color before you click.
- Settings persistence: height reference, transparency, and color are remembered and restored on next launch.

## Code

Main logic lives in `Sources/HighlightBar/main.swift`.
