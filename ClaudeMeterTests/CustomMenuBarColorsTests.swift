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

// MARK: - MenuBarHex.normalize

final class MenuBarHexTests: XCTestCase {
    func test_normalize_lowercaseNoHash_returnsCanonical() {
        XCTAssertEqual(MenuBarHex.normalize("00e5ff"), "#00E5FF")
    }
    func test_normalize_withHashAndWhitespace_returnsCanonical() {
        XCTAssertEqual(MenuBarHex.normalize("  #aabbcc  "), "#AABBCC")
    }
    func test_normalize_alreadyCanonical_isStable() {
        XCTAssertEqual(MenuBarHex.normalize("#FFFFFF"), "#FFFFFF")
    }
    func test_normalize_invalidInputs_returnNil() {
        XCTAssertNil(MenuBarHex.normalize("xyz"))
        XCTAssertNil(MenuBarHex.normalize("12345"))    // too short
        XCTAssertNil(MenuBarHex.normalize("1234567"))  // too long
        XCTAssertNil(MenuBarHex.normalize("GGGGGG"))   // non-hex letters
    }
}
