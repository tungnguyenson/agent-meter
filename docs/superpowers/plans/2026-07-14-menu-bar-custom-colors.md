# Custom Menu Bar Icon & Text Colors — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user set a custom icon color and text color for the Detailed menu-bar readout so it stays readable on any background, while the percentage keeps its usage-based color.

**Architecture:** Add three persisted fields to `AppSettings`. A tiny `MenuBarColorPalette.resolve(from:)` maps those settings to a `(icon, text)` NSColor pair (falling back to the current `.secondaryLabelColor` when disabled). `StatusItemController.updateDetailedMode` consumes the palette; a new conditional section in `AppearanceSettingsView` exposes a toggle + two `ColorPicker`s. Only the Detailed display mode is affected.

**Tech Stack:** Swift, SwiftUI + AppKit (Cocoa), XCTest. macOS app built with Xcode (`xcodebuild`).

## Global Constraints

- Platform floor: **macOS 14.0**. No new third-party dependencies.
- Xcode project uses **manually-maintained `project.pbxproj` with human-readable IDs** (e.g. `TST002`, `TST_SRC002`, `GRP_TESTS`). New files must be wired in by hand following that convention; do **not** introduce random UUIDs.
- Test target: `ClaudeMeterTests` (`TARGET002`), sources phase `SRC_PHASE002`. Framework: **XCTest**.
- Persisted color values are **hex strings** (`#RRGGBB`), consistent with the existing `Color(hex:)` / `Color.hexString` helpers in `ClaudeMeter/Extensions/Color+Extensions.swift`.
- Style: immutable patterns, `camelCase`, booleans prefixed `is/has/should/can` where applicable, early returns, no magic numbers. Match surrounding code.
- Scope is **Detailed mode only**. Do not touch Icon Only / Compact rendering, the popover, or the usage color palette.
- Backward compatibility: new settings keys must decode to defaults when absent (existing `decodeIfPresent` pattern).

**Build command (fast compile check):**
```bash
xcodebuild build -project ClaudeMeter.xcodeproj -scheme ClaudeMeter -configuration Debug -destination 'platform=macOS' 2>&1 | tail -8
```

**Run a single test class:**
```bash
xcodebuild test -project ClaudeMeter.xcodeproj -scheme ClaudeMeter -destination 'platform=macOS' -only-testing:ClaudeMeterTests/<ClassName> 2>&1 | tail -25
```

---

## File Structure

| File | Change | Responsibility |
|------|--------|----------------|
| `ClaudeMeter/Extensions/Color+Extensions.swift` | Modify | Harden `hexString` against grayscale color spaces |
| `ClaudeMeter/Core/Models/AppSettings.swift` | Modify | Persist the 3 new color settings |
| `ClaudeMeter/UI/MenuBar/StatusItemController.swift` | Modify | Add `MenuBarColorPalette` + apply it in Detailed rendering |
| `ClaudeMeter/UI/Settings/AppearanceSettingsView.swift` | Modify | Toggle + two color pickers (Detailed only) |
| `ClaudeMeterTests/CustomMenuBarColorsTests.swift` | Create | Unit tests for hexString fix, settings codable, palette |

No new source files are added to the **app** target (avoids `project.pbxproj` edits there). One new file is added to the **test** target (Task 1 wires it in once; later tasks append to it).

---

### Task 1: Harden `Color.hexString` for grayscale colors (fixes latent crash) + create test file

`ColorPicker` can hand back colors in a grayscale color space (e.g. pure white/black), whose `cgColor.components` has only 2 entries `[white, alpha]`. The current `hexString` indexes `[2]` → out-of-range crash. This task fixes it and stands up the shared test file.

**Files:**
- Create: `ClaudeMeterTests/CustomMenuBarColorsTests.swift`
- Modify: `ClaudeMeter.xcodeproj/project.pbxproj` (wire the test file into `ClaudeMeterTests`)
- Modify: `ClaudeMeter/Extensions/Color+Extensions.swift:42-52` (`hexString`)

**Interfaces:**
- Consumes: existing `Color.hexString` (String), `Color(nsColor:)`.
- Produces: hardened `Color.hexString` returning valid `#RRGGBB` for any color; shared test file `CustomMenuBarColorsTests.swift`.

- [ ] **Step 1: Create the test file**

Create `ClaudeMeterTests/CustomMenuBarColorsTests.swift`:

```swift
//
//  CustomMenuBarColorsTests.swift
//  ClaudeMeterTests
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import XCTest
import SwiftUI
import AppKit
@testable import ClaudeMeter

// MARK: - Color.hexString

final class ColorHexStringTests: XCTestCase {
    func test_hexString_forGrayscaleColor_returnsValidHex() {
        // NSColor(white:alpha:) lives in a grayscale color space whose cgColor
        // has only 2 components. The pre-fix code indexed [2] and crashed.
        let white = Color(nsColor: NSColor(white: 1.0, alpha: 1.0))
        let black = Color(nsColor: NSColor(white: 0.0, alpha: 1.0))

        XCTAssertEqual(white.hexString, "#FFFFFF")
        XCTAssertEqual(black.hexString, "#000000")
    }
}
```

- [ ] **Step 2: Wire the file into `project.pbxproj` (4 edits, readable IDs `TST010` / `TST_SRC010`)**

Edit A — add a `PBXBuildFile` entry (anchor on the MockURLProtocol build file line):

Replace:
```
		TST002 /* MockURLProtocol.swift in Sources */ = {isa = PBXBuildFile; fileRef = TST_SRC002; };
```
with:
```
		TST002 /* MockURLProtocol.swift in Sources */ = {isa = PBXBuildFile; fileRef = TST_SRC002; };
		TST010 /* CustomMenuBarColorsTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = TST_SRC010; };
```

Edit B — add a `PBXFileReference` entry:

Replace:
```
		TST_SRC002 /* MockURLProtocol.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MockURLProtocol.swift; sourceTree = "<group>"; };
```
with:
```
		TST_SRC002 /* MockURLProtocol.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MockURLProtocol.swift; sourceTree = "<group>"; };
		TST_SRC010 /* CustomMenuBarColorsTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CustomMenuBarColorsTests.swift; sourceTree = "<group>"; };
```

Edit C — add to the `GRP_TESTS` group children (anchored on the closing of that group):

Replace:
```
				TST_SRC002 /* MockURLProtocol.swift */,
			);
			path = ClaudeMeterTests;
```
with:
```
				TST_SRC002 /* MockURLProtocol.swift */,
				TST_SRC010 /* CustomMenuBarColorsTests.swift */,
			);
			path = ClaudeMeterTests;
```

Edit D — add to the test target `SRC_PHASE002` sources (anchored between two existing entries):

Replace:
```
				TST002 /* MockURLProtocol.swift in Sources */,
				TST003 /* KeychainServiceTests.swift in Sources */,
```
with:
```
				TST002 /* MockURLProtocol.swift in Sources */,
				TST010 /* CustomMenuBarColorsTests.swift in Sources */,
				TST003 /* KeychainServiceTests.swift in Sources */,
```

- [ ] **Step 3: Run the test to verify it fails (RED)**

Run:
```bash
xcodebuild test -project ClaudeMeter.xcodeproj -scheme ClaudeMeter -destination 'platform=macOS' -only-testing:ClaudeMeterTests/ColorHexStringTests 2>&1 | tail -25
```
Expected: FAIL — the process crashes / the test fails with an index-out-of-range fatal error inside `hexString` (thrown by the grayscale color). This proves the file is wired in and the bug reproduces.

- [ ] **Step 4: Apply the fix to `hexString`**

In `ClaudeMeter/Extensions/Color+Extensions.swift`, replace the `hexString` body:

```swift
    /// Convert to hex string
    var hexString: String {
        guard let components = NSColor(self).cgColor.components else {
            return "#000000"
        }

        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)

        return String(format: "#%02X%02X%02X", r, g, b)
    }
```

with:

```swift
    /// Convert to hex string
    var hexString: String {
        // Force sRGB so we always get 4 RGBA components. Colors from
        // ColorPicker (e.g. pure white/black) can be in a grayscale space
        // with only 2 components, which would crash a raw [2] index.
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else {
            return "#000000"
        }
        let components = srgb.cgColor.components ?? [0, 0, 0, 1]

        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)

        return String(format: "#%02X%02X%02X", r, g, b)
    }
```

- [ ] **Step 5: Run the test to verify it passes (GREEN)**

Run:
```bash
xcodebuild test -project ClaudeMeter.xcodeproj -scheme ClaudeMeter -destination 'platform=macOS' -only-testing:ClaudeMeterTests/ColorHexStringTests 2>&1 | tail -25
```
Expected: PASS (`Test Suite 'ColorHexStringTests' passed`).

- [ ] **Step 6: Commit**

```bash
git add ClaudeMeter/Extensions/Color+Extensions.swift ClaudeMeterTests/CustomMenuBarColorsTests.swift ClaudeMeter.xcodeproj/project.pbxproj
git commit -m "fix: harden Color.hexString against grayscale color spaces"
```

---

### Task 2: Add custom-color fields to `AppSettings` (persisted, backward-compatible)

**Files:**
- Modify: `ClaudeMeter/Core/Models/AppSettings.swift`
- Test: `ClaudeMeterTests/CustomMenuBarColorsTests.swift` (append a class)

**Interfaces:**
- Produces: `AppSettings.customMenuBarColorsEnabled: Bool` (default `false`), `AppSettings.menuBarIconColorHex: String` (default `"#FFFFFF"`), `AppSettings.menuBarTextColorHex: String` (default `"#FFFFFF"`). All `Codable`, decoding to defaults when keys are absent.

- [ ] **Step 1: Write the failing tests**

Append to `ClaudeMeterTests/CustomMenuBarColorsTests.swift`:

```swift
// MARK: - AppSettings color fields

final class AppSettingsColorFieldTests: XCTestCase {
    func test_encodeDecode_roundTripsCustomColorFields() throws {
        var settings = AppSettings()
        settings.customMenuBarColorsEnabled = true
        settings.menuBarIconColorHex = "#112233"
        settings.menuBarTextColorHex = "#AABBCC"

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertTrue(decoded.customMenuBarColorsEnabled)
        XCTAssertEqual(decoded.menuBarIconColorHex, "#112233")
        XCTAssertEqual(decoded.menuBarTextColorHex, "#AABBCC")
    }

    func test_decode_missingColorKeys_usesDefaults() throws {
        // JSON persisted by an older build without the new keys.
        let json = Data(#"{"displayMode":"Compact"}"#.utf8)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertFalse(decoded.customMenuBarColorsEnabled)
        XCTAssertEqual(decoded.menuBarIconColorHex, "#FFFFFF")
        XCTAssertEqual(decoded.menuBarTextColorHex, "#FFFFFF")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run:
```bash
xcodebuild test -project ClaudeMeter.xcodeproj -scheme ClaudeMeter -destination 'platform=macOS' -only-testing:ClaudeMeterTests/AppSettingsColorFieldTests 2>&1 | tail -25
```
Expected: FAIL to compile — `value of type 'AppSettings' has no member 'customMenuBarColorsEnabled'`.

- [ ] **Step 3: Add the fields, coding keys, and decode lines**

In `ClaudeMeter/Core/Models/AppSettings.swift`:

3a. After the line `var showExtraUsage: Bool = false` (in the `// Display` group), add:
```swift
    var customMenuBarColorsEnabled: Bool = false
    var menuBarIconColorHex: String = "#FFFFFF"
    var menuBarTextColorHex: String = "#FFFFFF"
```

3b. In `private enum CodingKeys`, after `case showExtraUsage`, add:
```swift
        case customMenuBarColorsEnabled
        case menuBarIconColorHex
        case menuBarTextColorHex
```

3c. In `init(from decoder:)`, after the `showExtraUsage = ...` line, add:
```swift
        customMenuBarColorsEnabled = try container.decodeIfPresent(Bool.self, forKey: .customMenuBarColorsEnabled) ?? defaults.customMenuBarColorsEnabled
        menuBarIconColorHex = try container.decodeIfPresent(String.self, forKey: .menuBarIconColorHex) ?? defaults.menuBarIconColorHex
        menuBarTextColorHex = try container.decodeIfPresent(String.self, forKey: .menuBarTextColorHex) ?? defaults.menuBarTextColorHex
```

- [ ] **Step 4: Run to verify pass**

Run:
```bash
xcodebuild test -project ClaudeMeter.xcodeproj -scheme ClaudeMeter -destination 'platform=macOS' -only-testing:ClaudeMeterTests/AppSettingsColorFieldTests 2>&1 | tail -25
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ClaudeMeter/Core/Models/AppSettings.swift ClaudeMeterTests/CustomMenuBarColorsTests.swift
git commit -m "feat: add custom menu bar color settings to AppSettings"
```

---

### Task 3: Add `MenuBarColorPalette` resolver

**Files:**
- Modify: `ClaudeMeter/UI/MenuBar/StatusItemController.swift` (add a top-level `struct` in the same file — no new file, so no pbxproj edit)
- Test: `ClaudeMeterTests/CustomMenuBarColorsTests.swift` (append a class)

**Interfaces:**
- Consumes: `AppSettings` (Task 2), `Color(hex:)`, `Color.hexString` (Task 1).
- Produces: `struct MenuBarColorPalette { let icon: NSColor; let text: NSColor; static func resolve(from settings: AppSettings) -> MenuBarColorPalette }`. When `customMenuBarColorsEnabled == false`, both colors are `.secondaryLabelColor`.

- [ ] **Step 1: Write the failing tests**

Append to `ClaudeMeterTests/CustomMenuBarColorsTests.swift`:

```swift
// MARK: - MenuBarColorPalette

final class MenuBarColorPaletteTests: XCTestCase {
    func test_resolve_whenDisabled_usesSecondaryLabelColor() {
        var settings = AppSettings()
        settings.customMenuBarColorsEnabled = false

        let palette = MenuBarColorPalette.resolve(from: settings)

        XCTAssertEqual(palette.icon, NSColor.secondaryLabelColor)
        XCTAssertEqual(palette.text, NSColor.secondaryLabelColor)
    }

    func test_resolve_whenEnabled_usesConfiguredHexColors() {
        var settings = AppSettings()
        settings.customMenuBarColorsEnabled = true
        settings.menuBarIconColorHex = "#FF0000"
        settings.menuBarTextColorHex = "#00FF00"

        let palette = MenuBarColorPalette.resolve(from: settings)

        XCTAssertEqual(Color(nsColor: palette.icon).hexString, "#FF0000")
        XCTAssertEqual(Color(nsColor: palette.text).hexString, "#00FF00")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run:
```bash
xcodebuild test -project ClaudeMeter.xcodeproj -scheme ClaudeMeter -destination 'platform=macOS' -only-testing:ClaudeMeterTests/MenuBarColorPaletteTests 2>&1 | tail -25
```
Expected: FAIL to compile — `cannot find 'MenuBarColorPalette' in scope`.

- [ ] **Step 3: Add the `MenuBarColorPalette` struct**

In `ClaudeMeter/UI/MenuBar/StatusItemController.swift`, add this top-level struct at the end of the file (after the closing brace of `class StatusItemController`). The file already imports `Cocoa` and `SwiftUI`:

```swift
// MARK: - Menu Bar Color Palette

/// Resolves the icon and text colors for the Detailed menu-bar mode.
/// When custom colors are disabled the app falls back to the adaptive
/// `.secondaryLabelColor` — its original appearance.
struct MenuBarColorPalette {
    let icon: NSColor
    let text: NSColor

    static func resolve(from settings: AppSettings) -> MenuBarColorPalette {
        guard settings.customMenuBarColorsEnabled else {
            return MenuBarColorPalette(icon: .secondaryLabelColor, text: .secondaryLabelColor)
        }
        return MenuBarColorPalette(
            icon: NSColor(Color(hex: settings.menuBarIconColorHex)),
            text: NSColor(Color(hex: settings.menuBarTextColorHex))
        )
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run:
```bash
xcodebuild test -project ClaudeMeter.xcodeproj -scheme ClaudeMeter -destination 'platform=macOS' -only-testing:ClaudeMeterTests/MenuBarColorPaletteTests 2>&1 | tail -25
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ClaudeMeter/UI/MenuBar/StatusItemController.swift ClaudeMeterTests/CustomMenuBarColorsTests.swift
git commit -m "feat: add MenuBarColorPalette resolver for detailed mode"
```

---

### Task 4: Apply the palette in Detailed-mode rendering

Thread the resolved palette through the Detailed-mode string builders so the clock/calendar icons and time labels take the custom colors, while the `%` keeps its usage color. (AppKit menu-bar rendering is verified by build + manual check.)

**Files:**
- Modify: `ClaudeMeter/UI/MenuBar/StatusItemController.swift` (`updateMenuBarDisplay`, `updateDetailedMode`, `windowSegment`, `dividerString`, `mutedTitle`)

**Interfaces:**
- Consumes: `MenuBarColorPalette.resolve(from:)` (Task 3).
- Produces: Detailed rendering that uses `palette.icon` for symbols, `palette.text` for time labels / placeholders, and `palette.text.withAlphaComponent(0.5)` for the divider. `%` unchanged (`ColorTheme.nsColorForUsage`).

- [ ] **Step 1: Resolve the palette at the call site**

In `updateMenuBarDisplay(with:settings:)`, replace the `.detailed` case:
```swift
        case .detailed:
            updateDetailedMode(button: button, data: data, style: settings.detailedModeStyle)
```
with:
```swift
        case .detailed:
            let palette = MenuBarColorPalette.resolve(from: settings)
            updateDetailedMode(button: button, data: data, style: settings.detailedModeStyle, palette: palette)
```

- [ ] **Step 2: Thread the palette through `updateDetailedMode`**

Replace the whole `updateDetailedMode` method with:
```swift
    private func updateDetailedMode(button: NSStatusBarButton, data: UsageData?, style: DetailedModeStyle, palette: MenuBarColorPalette) {
        button.image = nil

        guard let data = data else {
            button.attributedTitle = mutedTitle("-- | --", color: palette.text)
            return
        }

        var segments: [NSAttributedString] = []

        if let fiveHour = data.fiveHour {
            segments.append(windowSegment(fiveHour, symbol: "clock", fixedLabel: "5h", style: style, units: .hoursMinutes, palette: palette))
        }

        if let sevenDay = data.sevenDay {
            segments.append(windowSegment(sevenDay, symbol: "calendar", fixedLabel: "7d", style: style, units: .daysHours, palette: palette))
        }

        guard !segments.isEmpty else {
            button.attributedTitle = mutedTitle("No data", color: palette.text)
            return
        }

        let title = NSMutableAttributedString()
        for (index, segment) in segments.enumerated() {
            if index > 0 { title.append(dividerString(color: palette.text)) }
            title.append(segment)
        }
        button.attributedTitle = title
    }
```

- [ ] **Step 3: Update `windowSegment` to take the palette**

Replace the whole `windowSegment(...)` method with:
```swift
    private func windowSegment(
        _ window: UsageWindow,
        symbol: String,
        fixedLabel: String,
        style: DetailedModeStyle,
        units: CountdownUnits,
        palette: MenuBarColorPalette
    ) -> NSAttributedString {
        let usage = window.utilization

        let trailing: String
        switch style {
        case .fixed:
            trailing = fixedLabel
        case .countdown:
            trailing = countdownLabel(until: window.resetsAt, units: units) ?? fixedLabel
        }

        let segment = NSMutableAttributedString()
        segment.append(symbolString(symbol, color: palette.icon))
        segment.append(NSAttributedString(string: "  ", attributes: [.font: labelFont]))
        segment.append(NSAttributedString(string: "\(Int(usage))%", attributes: [
            .foregroundColor: ColorTheme.nsColorForUsage(usage),
            .font: percentFont
        ]))
        segment.append(NSAttributedString(string: " ", attributes: [.font: labelFont]))
        segment.append(NSAttributedString(string: trailing, attributes: [
            .foregroundColor: palette.text,
            .font: labelFont
        ]))
        return segment
    }
```

- [ ] **Step 4: Update `dividerString` and `mutedTitle` to take a color**

Replace the whole `dividerString()` method with:
```swift
    /// Thin vertical divider drawn between the two windows.
    private func dividerString(color: NSColor) -> NSAttributedString {
        return NSAttributedString(string: "  |  ", attributes: [
            .foregroundColor: color.withAlphaComponent(0.5),
            .font: labelFont
        ])
    }
```

Replace the whole `mutedTitle(_:)` method with:
```swift
    /// Neutral placeholder title used for the no-data / loading states.
    private func mutedTitle(_ string: String, color: NSColor) -> NSAttributedString {
        return NSAttributedString(string: string, attributes: [
            .foregroundColor: color,
            .font: labelFont
        ])
    }
```

- [ ] **Step 5: Build to verify it compiles**

Run:
```bash
xcodebuild build -project ClaudeMeter.xcodeproj -scheme ClaudeMeter -configuration Debug -destination 'platform=macOS' 2>&1 | tail -8
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Run the full test suite (no regressions)**

Run:
```bash
xcodebuild test -project ClaudeMeter.xcodeproj -scheme ClaudeMeter -destination 'platform=macOS' 2>&1 | tail -30
```
Expected: all tests pass. (Rendering logic itself is verified manually in Task 5.)

- [ ] **Step 7: Commit**

```bash
git add ClaudeMeter/UI/MenuBar/StatusItemController.swift
git commit -m "feat: apply custom color palette in detailed menu bar mode"
```

---

### Task 5: Add the Appearance settings UI (toggle + color pickers) + end-to-end manual verification

**Files:**
- Modify: `ClaudeMeter/UI/Settings/AppearanceSettingsView.swift`

**Interfaces:**
- Consumes: `AppSettings.customMenuBarColorsEnabled` / `menuBarIconColorHex` / `menuBarTextColorHex` (Task 2), `Color(hex:)` / `Color.hexString` (Task 1). The existing `$appState.settings` publishing path drives the live menu-bar update (same pattern as the existing `displayMode` picker).

- [ ] **Step 1: Add color bindings + the conditional section**

In `ClaudeMeter/UI/Settings/AppearanceSettingsView.swift`, add two computed bindings inside `struct AppearanceSettingsView` (e.g. just above `var body`):
```swift
    private var iconColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: appState.settings.menuBarIconColorHex) },
            set: { appState.settings.menuBarIconColorHex = $0.hexString }
        )
    }

    private var textColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: appState.settings.menuBarTextColorHex) },
            set: { appState.settings.menuBarTextColorHex = $0.hexString }
        )
    }
```

Then, inside the `Form`, immediately after the closing `}` of the `Section(header: Text("Color Scheme"))` block, add:
```swift
                if appState.settings.displayMode == .detailed {
                    Section(header: Text("Menu Bar Colors")) {
                        Toggle("Custom icon & text colors", isOn: $appState.settings.customMenuBarColorsEnabled)

                        if appState.settings.customMenuBarColorsEnabled {
                            ColorPicker("Icon color", selection: iconColorBinding, supportsOpacity: false)
                            ColorPicker("Text color", selection: textColorBinding, supportsOpacity: false)
                        }

                        Text("Applies to Detailed mode. The percentage still changes color by usage level.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
xcodebuild build -project ClaudeMeter.xcodeproj -scheme ClaudeMeter -configuration Debug -destination 'platform=macOS' 2>&1 | tail -8
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual end-to-end verification**

Build and launch the release app:
```bash
./scripts/build-app.sh && open build/Build/Products/Release/ClaudeMeter.app
```
Then verify:
1. Open Settings → **Appearance**. With Display Mode = **Compact**, the "Menu Bar Colors" section is **not** shown.
2. Set Display Mode = **Detailed** → the "Menu Bar Colors" section appears; the toggle is **off** by default and the menu bar shows the original muted-gray icons/labels with the colored `%`.
3. Turn the toggle **on** → two color pickers appear.
4. Set Icon color = white, Text color = cyan → the clock/calendar icons and the `5h`/`7d` labels update **live** in the menu bar; the `%` still shows its usage color (green/yellow/orange/red).
5. Turn the toggle **off** → the readout returns to muted gray.
6. Confirm **Icon Only** and **Compact** modes look unchanged (progress ring still usage-colored).
7. Quit and relaunch the app → the toggle state and chosen colors persist.

- [ ] **Step 4: Commit**

```bash
git add ClaudeMeter/UI/Settings/AppearanceSettingsView.swift
git commit -m "feat: add custom menu bar color controls to Appearance settings"
```

---

## Self-Review

**Spec coverage:**
- Data model (3 fields, CodingKeys, init, defaults, backward compat) → Task 2. ✅
- Settings UI (conditional section, toggle, two color pickers, caption, hex bindings) → Task 5. ✅
- Rendering (palette resolve; icon→iconColor, labels→textColor, divider→textColor@0.5α, `%` unchanged, placeholder→textColor; live update via existing subscription) → Tasks 3 + 4. ✅
- Edge case: toggle off restores original behavior → Task 3 (palette fallback) + Task 5 manual step 5. ✅
- Edge case: grayscale `hexString` crash fix → Task 1. ✅
- Out of scope (Icon Only/Compact/popover/usage palette) → untouched; guarded by Task 5 manual step 6. ✅
- Testing: codable round-trip + backward compat + grayscale hex + palette → Tasks 1-3; manual for rendering/UI → Tasks 4-5. ✅

**Placeholder scan:** No TBD/TODO; every code step shows complete code and exact commands. ✅

**Type consistency:** `MenuBarColorPalette` (`icon`/`text`, `resolve(from:)`) defined in Task 3 and used identically in Task 4. `customMenuBarColorsEnabled` / `menuBarIconColorHex` / `menuBarTextColorHex` named identically across Tasks 2, 3, 5. `hexString` / `Color(hex:)` signatures unchanged. ✅

## Trade-off (from spec, accepted)

Custom colors are fixed and do **not** auto-invert between Light/Dark appearance, unlike the default adaptive gray. The user picks colors that suit their own menu-bar background. The default value is white (`#FFFFFF`), adjustable the moment the toggle is enabled.
