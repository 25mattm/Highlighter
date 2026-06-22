# Highlight Bar (macOS + Windows)

A lightweight click-through reading bar that follows your mouse across screens and
stays on top of every window, so you can track the line you are reading.

- `HighlightBar/` — macOS Swift menu-bar app
- `WindowsHighlightBar/` — Windows C# WinForms app

> **This pass is macOS-focused.** The macOS app has gained reading overlays, lock
> mode, reading profiles, launch-at-login, and more (see the table below); the
> Windows app still implements the shared baseline. The two apps **intentionally
> drift** until a later Windows catch-up pass — tracked in
> [`BACKLOG.md`](BACKLOG.md).

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

### Shared baseline (both platforms)

| Feature | macOS | Windows |
| --- | --- | --- |
| Always-on-top translucent bar | ✅ | ✅ |
| Click-through (clicks, scrolling, typing pass through) | ✅ | ✅ |
| Follows the mouse across multiple screens | ✅ | ✅ |
| Size control (font-size reference `10`–`100`) | ✅ | ✅ |
| Opacity / transparency control (`10%`–`90%`) | ✅ | ✅ |
| Color selection with hover preview | ✅ | ✅ |
| Global show/hide shortcut (`Ctrl/⌘ + Shift + H`) | ✅ | ✅ |
| Remembers last-used settings | ✅ (`UserDefaults`) | ✅ (`%APPDATA%\HighlightBar\settings.json`) |

### macOS additions (this pass)

| Feature | macOS | Windows |
| --- | --- | --- |
| Live display-change re-clamp (resolution / plug-unplug) | ✅ | ⏳ later |
| Lock / pin position + nudge (`⌘⇧L`, `⌘⇧↑/↓`) | ✅ | ⏳ later |
| Spotlight overlay (dims all but a slot at the bar) | ✅ | ⏳ later |
| Screen-tint overlay (uniform colored wash) | ✅ | ⏳ later |
| Bar shape (ruler / line) + vertical column orientation | ✅ | ⏳ later |
| Tracking source (mouse / scroll / keyboard) | ✅ | ⏳ later |
| Profiles (Dyslexia, ADHD / Focus, Low vision + custom) | ✅ | ⏳ later |
| Launch at login | ✅ | ⏳ later |
| First-run onboarding + VoiceOver-aware accessibility | ✅ | ⏳ later |
| Opt-in auto-update (Sparkle) | ✅ (scaffolded) | ⏳ later |

The control surface is platform-idiomatic: macOS uses in-menu sliders, a color
swatch row, and submenus; Windows uses tray context-menu items and a color submenu.

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

The macOS release is signed (Developer ID), notarized, stapled, and ships an
opt-in Sparkle auto-updater. That requires a one-time setup of Apple and Sparkle
credentials as GitHub secrets/variables — see [`RELEASE.md`](RELEASE.md) for the
exact checklist.

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
