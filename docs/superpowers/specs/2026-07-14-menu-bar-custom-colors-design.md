# Design: Custom icon & text colors for the menu bar (Detailed mode)

**Date:** 2026-07-14
**Status:** Approved (pending implementation plan)

## Problem

The menu bar in **Detailed** display mode renders the clock/calendar icons and the
time labels (`5h` / `7d` or the countdown) in `.secondaryLabelColor` — a muted,
adaptive gray. On colored menu-bar backgrounds (tinted wallpapers, light desktops)
this gray can be too faint to read. The user wants to override these colors manually
so the readout is legible against their own background.

## Goal

Let the user set a **custom icon color** and a **custom text color** for the
menu-bar readout, primarily so it stays readable on any background.

## Scope decisions (settled during brainstorming)

1. **Motivation:** readability on any background — the user wants manual control over
   contrast, not a full theming system.
2. **The `%` keeps its usage-based color** (green → yellow → orange → red). Custom
   colors apply only to the "neutral" chrome: the icons and the time labels.
3. **Icon color applies only to the clock/calendar SF Symbols in Detailed mode.**
   The progress ring in Icon Only / Compact modes stays usage-colored (it *is* the
   usage signal) and is out of scope.
4. **Control model — Approach A:** a toggle plus two color pickers.

### Out of scope

- Icon Only / Compact modes (progress ring) — untouched.
- The popover UI — untouched.
- Customizing the usage color palette (green/yellow/orange/red) — untouched.
- Per-appearance (Light vs Dark) color variants — a single fixed color per control.

## Design

### 1. Data model — `ClaudeMeter/Core/Models/AppSettings.swift`

Add three fields with defaults (backward-compatible via the existing
`decodeIfPresent` pattern):

```swift
var customMenuBarColorsEnabled: Bool = false
var menuBarIconColorHex: String = "#FFFFFF"
var menuBarTextColorHex: String = "#FFFFFF"
```

- Add all three to `CodingKeys`.
- Add all three to `init(from:)` with `decodeIfPresent(...) ?? defaults.<field>` so
  existing persisted settings decode without the new keys.
- Default color is white (high contrast); the user adjusts it in the picker. The
  default only takes visible effect the moment the toggle is turned on — while the
  toggle is off, the current adaptive gray is preserved.

### 2. Settings UI — `ClaudeMeter/UI/Settings/AppearanceSettingsView.swift`

Add a new `Section(header: Text("Menu Bar Colors"))` that is shown **only when
`appState.settings.displayMode == .detailed`** (mirrors how the "Detailed Label"
picker is already shown conditionally).

Contents:
- `Toggle("Custom icon & text colors", isOn: $appState.settings.customMenuBarColorsEnabled)`
  — default off.
- When enabled, two color pickers:
  - `ColorPicker("Icon color", selection: iconColorBinding, supportsOpacity: false)`
  - `ColorPicker("Text color", selection: textColorBinding, supportsOpacity: false)`
- A small caption: "Applies to Detailed mode. The percentage still changes color by
  usage level."

Bridge `Color ⇄ hex` with a computed `Binding<Color>` for each picker, using the
existing `Color(hex:)` initializer and `.hexString` property from
`ClaudeMeter/Extensions/Color+Extensions.swift`:

```swift
private var iconColorBinding: Binding<Color> {
    Binding(
        get: { Color(hex: appState.settings.menuBarIconColorHex) },
        set: { appState.settings.menuBarIconColorHex = $0.hexString }
    )
}
```
(analogous for text).

### 3. Rendering — `ClaudeMeter/UI/MenuBar/StatusItemController.swift`

In `updateDetailedMode`, resolve the palette once and thread it through the segment
builders:

- If `settings.customMenuBarColorsEnabled`:
  - `iconColor = NSColor(Color(hex: settings.menuBarIconColorHex))`
  - `textColor = NSColor(Color(hex: settings.menuBarTextColorHex))`
- Else (current behavior):
  - `iconColor = .secondaryLabelColor`
  - `textColor = .secondaryLabelColor`

Apply:
- `symbolString(symbol, color: iconColor)` for the clock/calendar glyphs.
- The trailing time label (`5h`/`7d`/countdown) uses `textColor`.
- The `|` divider uses `textColor` with a reduced alpha (e.g. `.withAlphaComponent(0.5)`)
  to preserve the current visual hierarchy (was `.tertiaryLabelColor`).
- The `%` run stays `ColorTheme.nsColorForUsage(usage)` — **unchanged**.
- The no-data / loading placeholder (`mutedTitle`) uses `textColor` when custom is on,
  else `.secondaryLabelColor`.

Implementation note: `updateDetailedMode` currently forwards only `style` to
`windowSegment`. Extend the relevant helper signatures (or pass a small resolved
`(iconColor, textColor)` pair) so the two colors reach `windowSegment`,
`symbolString`, `dividerString`, and `mutedTitle`. Keep the change surgical.

The existing Combine subscription already re-renders on `appState.$settings` changes
(`CombineLatest(appState.$usageData, appState.$settings)`), so toggling the setting or
changing a color updates the menu bar **live**, with no restart.

### 4. Edge cases & a latent-bug fix

- **Toggle off restores exactly the current behavior** (secondary/tertiary label
  colors). No regression when the feature is unused.
- **Grayscale color-space crash (must fix):** `Color.hexString` reads
  `NSColor(self).cgColor.components[0..2]`. If `ColorPicker` returns a color in a
  grayscale color space (e.g. the user picks pure white or black), that `cgColor`
  has only 2 components (`[white, alpha]`), so indexing `[2]` is out of range and
  crashes. This feature exercises that path directly. Fix: convert to sRGB before
  reading components, e.g. `NSColor(self).usingColorSpace(.sRGB)` (fall back to the
  original if the conversion returns nil). Scoped, justified fix.
- **Invalid/empty hex:** `Color(hex:)` already falls back to black for malformed
  input; values are produced by the picker so this is a safety net, not a normal path.
- Icon Only / Compact / popover: unaffected.

### 5. Testing

**Unit** (`ClaudeMeterTests/`, XCTest — matches existing suite):
- `AppSettings` encode → decode round-trip preserves the three new fields.
- Decoding settings JSON **missing** the new keys yields the defaults
  (`false`, `#FFFFFF`, `#FFFFFF`) — backward compatibility.
- `Color.hexString` round-trip for a grayscale-derived color (pure white) does **not**
  crash and returns `#FFFFFF` (regression test for the fix above).

**Manual verification:**
- Build via `./scripts/build-app.sh`, launch, switch to **Detailed** mode.
- Enable custom colors; set icon = white, text = cyan → menu bar updates live; the
  `%` still changes color by usage level; the divider/labels take the new colors.
- Toggle off → the readout returns to the muted gray look.
- Confirm Icon Only / Compact modes are visually unchanged.

## Trade-off (accepted)

Custom colors are fixed values; unlike the default adaptive gray, they do **not**
auto-invert between Light and Dark appearance. The user picks a color that suits their
own menu-bar background. This is acceptable given the goal (force contrast for a known
setup) and is surfaced here explicitly.
