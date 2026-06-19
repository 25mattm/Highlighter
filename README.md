# Highlight Bar (macOS + Windows)

A lightweight click-through reading bar that follows your mouse across screens and
stays on top of every window, so you can track the line you are reading. Two native
apps share the same feature set:

- `HighlightBar/` — macOS Swift menu-bar app
- `WindowsHighlightBar/` — Windows C# WinForms app

## Accessibility

Highlight Bar is a digital reading guide. Many people who read more comfortably with
a physical reading ruler or line guide — including readers with dyslexia, visual
tracking difficulties, ADHD, or low vision — lose their place when moving between
lines or across a wide screen. The bar gives a consistent, adjustable visual anchor
that follows the cursor, while staying fully click-through so it never interrupts
normal work.

Accessibility-minded design choices:

- **Click-through everywhere** — the overlay never blocks clicks, scrolling, or typing.
- **Adjustable to the reader** — size, color, and opacity are tunable so the guide is
  visible without obscuring text, and the last-used settings are remembered.
- **Quick show/hide** — a global `Ctrl/⌘ + Shift + H` shortcut toggles the bar instantly,
  so it is there when reading and gone when it would get in the way.
- **No sign-in, no network, no data collection** — it is a purely local utility.

## Features

Both platforms implement the same behaviour:

| Feature | macOS | Windows |
| --- | --- | --- |
| Always-on-top translucent bar | ✅ | ✅ |
| Click-through (normal clicks pass through) | ✅ | ✅ |
| Follows the mouse across multiple screens | ✅ | ✅ |
| Font-size reference control (`10`–`100`, height = 2× reference) | ✅ | ✅ |
| Opacity / transparency control (`10%`–`90%`) | ✅ | ✅ |
| Color selection with hover preview | ✅ | ✅ |
| Rounded bar with outlined border | ✅ | ✅ |
| Global show/hide shortcut (`Ctrl/⌘ + Shift + H`) | ✅ | ✅ |
| Remembers last-used settings | ✅ (`UserDefaults`) | ✅ (`%APPDATA%\HighlightBar\settings.json`) |

The control surface is platform-idiomatic: macOS uses in-menu sliders and a color
swatch row; Windows uses tray context-menu items and a color submenu.

## Downloads for friends

- Windows: from the artifact in **Build Windows App** or from GitHub Releases (`HighlightBar-windows-x64.zip`).
- macOS: from the artifact in **Build macOS App** or from GitHub Releases (`HighlightBar-macos.zip`).
- Quick start: `QUICK_START.md`
- Full usage guide: `USER_GUIDE.md`

## Releases

Public release downloads are produced automatically when a version tag is pushed:

```bash
git tag v0.1.2
git push origin v0.1.2
```

That triggers **Release Windows App** → `HighlightBar-windows-x64.zip` and
**Release macOS App** → `HighlightBar-macos.zip`.

## Building locally

### macOS

```bash
cd HighlightBar
swift run            # run directly
./scripts/build-app.sh   # build dist/HighlightBar.app
```

### Windows (on a Windows machine)

```powershell
cd WindowsHighlightBar
dotnet publish .\HighlightBar.Windows.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o .\publish\win-x64
```

The executable will be in `WindowsHighlightBar\publish\win-x64`.

## Notes

- CI builds the macOS app on `macos-latest` and the Windows app on `windows-latest`,
  so neither toolchain is required locally to ship both.
- See the per-app READMEs in `HighlightBar/` and `WindowsHighlightBar/` for details.

## License

MIT — see `LICENSE`.
