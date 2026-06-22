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

- **Overlay palette:** the spotlight dim reuses the shared 6-color palette; the
  darkest option is `Gray`. A dedicated dark/black option would dim more
  effectively. (Would also touch the shared color list.)
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
