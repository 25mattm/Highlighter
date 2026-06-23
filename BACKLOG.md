# Backlog

Deferred work, tracked here so the macOS-focused pass can ship without scope
creep. Nothing here is built yet.

## 1. Windows parity (separate later pass)

The macOS app (`HighlightBar/`) advanced well past the Windows app
(`WindowsHighlightBar/`) this pass; the two **intentionally drift** until Windows
catches up. To reach parity, bring these macOS features to the WinForms app:

- Live display-change handling (reposition/re-clamp on resolution or monitor
  changes).
- Lock / pin position + nudge, with persisted lock state and position.
- Screen overlays: spotlight (dim with a cursor-following cutout) and screen
  tint, one per monitor, click-through, below the bar.
- Bar shape (ruler vs thin line) and vertical/column orientation.
- Tracking source: mouse / scroll / keyboard (mind the Windows equivalents of
  the macOS permission story).
- Profiles: built-ins (Dyslexia, ADHD / Focus, Low vision) + user-saved presets.
- Launch at login (Windows Startup), first-run onboarding, accessibility review.
- Auto-update (the Windows updater story is separate from Sparkle).

Keep the settings model and naming aligned with the macOS `Settings` so behavior
matches across platforms.

## 2. App Store distribution + StoreKit monetization (free-vs-pro)

Revisit when monetization is on the table. Two parts:

- **Distribution:** an App Store build differs from the current Developer ID +
  notarized direct download — it requires the App Sandbox, which currently is
  **intentionally disabled** because it would block the screen overlays and the
  global Carbon hotkeys. A sandboxed build would need to rework those (e.g.
  entitlements/temporary exceptions, or dropping global hotkeys inside the
  sandboxed target). The direct-download build stays the primary channel.
- **Free-vs-pro gating points** (where a paywall would naturally sit):
  - **Spotlight overlay** (Phase 3, `OverlayController` spotlight style) — the
    headline "pro" feature.
  - **Profiles** (Phase 4, `Profiles.swift`) — built-ins could stay free with
    custom saved profiles gated, or the whole profiles submenu gated.
  - Screen-tint and the basic bar/size/color/opacity should stay free.

  Implementation note: gate at apply-time in `applyMode` (spotlight) and
  `applyProfile` / `saveCurrentAsProfile` (profiles), surfacing an upgrade
  prompt instead of applying when unlicensed.

## 3. macOS TODOs (hit during this pass)

- **Overlay palette:** ~~the spotlight dim's darkest preset is `Gray`~~ — resolved
  by v3 custom colors (`Custom Overlay Color…` can pick true black for a stronger
  dim). The 6 presets still skew light; a darker preset could still be a nice
  default.
- **App icon:** the menu-bar item shows the text `HB` and the bundle has no real
  app icon (`CFBundleIconFile`). Add an icon set for the `.app`.
- **Sparkle appcast hosting:** `SUFeedURL` defaults to a GitHub Pages URL that
  must actually be hosted, and `SUPublicEDKey` is a placeholder until the real
  key is set (see `RELEASE.md`). No appcast is published yet.
- **Keyboard tracking permission UX:** granting Input Monitoring requires the
  user to re-select `Tracking → Keyboard` afterward; there's no live re-detect of
  the permission once granted.
- **Vertical-orientation nudge:** while locked, `⌘⇧↑/↓` nudges along the bar's
  free axis, so for a vertical column it moves left/right — works, but the
  up/down keys feel indirect there.
- **Last-applied profile checkmark** can go stale: it stays checked after manual
  tweaks (no auto-clear) — cosmetic only.
- **No automated tests:** the SPM package has no test target. `BarGeometry`,
  `Settings` (Codable round-trip/migration), and `ProfileStore` are the
  most unit-testable seams if/when tests are added.

## 4. v3 feature ideas (competitive scan, June 2026)

**Guiding principle: accessibility is the priority.** Highlight Bar is first a
reading aid for dyslexia, ADHD, low vision, and visual stress. Reader-serving
features come first; presentation/cursor-highlight features are an *adjacent*
track that can help fund the app but must not displace the mission or crowd the
UI. Keep the accessibility core free, click-through, no-permission, and local.

Landscape: closest direct competitor is **Overdys** (Mac App Store, same
ruler/line/overlay model). Adjacent markets: focus-dimmers (HazeOver ~$5 once,
Blurred free) and cursor-highlighters (Mouseposé ~$10/yr, Presentify ~$8/yr,
Presenter Pointer $9.99 once). Reading/tint aids trend free–cheap. Our
differentiator: few apps combine reading-guide + focus-dim + cursor-highlight,
cursor-following across multiple monitors, scroll/keyboard tracking, profiles,
and a no-permission, fully click-through overlay.

### Done (v3 so far, on `app-store`)
- Custom colors via NSColorPanel (bar + overlays) — precise visual-stress tints.
- Per-app auto-enable (NSWorkspace, no permission).

### Accessibility-first (do next, rough priority order)
- **Read-aloud / text-to-speech** of selected text — high impact for dyslexia /
  low vision. Needs the selected text (Services / Accessibility) → opt-in.
- **Caret-follow tracking** — bar follows the text cursor while typing/reading;
  big for dyslexia when writing. Accessibility API → opt-in.
- **Larger / higher-contrast options** — bigger max bar size, bolder border,
  higher max opacity; review low-vision-friendly defaults.
- **Scheduled / automatic tint** — visual-stress relief on a schedule or per app.
- **Peek hotkey** (hold-to-hide), **custom hotkey remapping**, **crosshair**
  (H+V together) — all no-permission; improve control accessibility.
- **Reading-window variants** — dim above/below the active line, or a
  double-line bracket around it.

### Adjacent / funding track (secondary — must not displace the above)
- Radial/circle spotlight cutout + click ripple — opens the presenter market
  (Mouseposé/Presentify) and reuses the overlay engine; no permission.
- Keystroke display (Input Monitoring → opt-in).
- HazeOver-style "focus active window" dimming (Accessibility → opt-in).

### Permission posture
Mouse tracking and every current feature stay permission-free. Anything needing
a TCC permission (read-aloud, caret-follow, keystroke display, focus-window) is
strictly opt-in with a clear explanation, mirroring the keyboard-tracking flow.

### Monetization mapping (ties to §2; revisit only when monetizing)
- Free (the mission): bar, size/color/opacity, custom colors, screen tint, basic
  profiles, per-app auto-enable — the accessibility core stays free.
- Possible paid/pro: spotlight (incl. radial), the presentation pack, custom
  profiles. Category pricing → low one-time (~$5–10) or small sub (~$8–10/yr).
