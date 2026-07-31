//
//  ColorTheme.swift
//  AgentMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI

/// Color theme for AgentMeter
/// Based on Apple Human Interface Guidelines color palette
enum ColorTheme {
    // MARK: - Usage Colors

    /// Builds a `Color` that resolves to a different RGB value per appearance.
    /// The usage colors below double as both ring/text tint, and the flat
    /// Apple system-tint values (tuned to pop against a dark menu bar) measure
    /// under 2:1 contrast against the popover's light gray provider cards —
    /// well short of the 4.5:1 WCAG AA minimum for text. `light` swaps in a
    /// darker, more saturated shade there; `dark` keeps the original vivid one.
    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    /// Green - Low usage (0-50%). Light variant is GitHub Primer's accessible
    /// "success" green (#1A7F37, ~5:1 on white); dark keeps Apple's #34C759.
    static let green = adaptiveColor(
        light: NSColor(red: 26/255, green: 127/255, blue: 55/255, alpha: 1),
        dark: NSColor(red: 52/255, green: 199/255, blue: 89/255, alpha: 1)
    )

    /// Yellow - Medium usage (50-75%). Light variant is Primer's "attention"
    /// gold (#9A6700, ~4.9:1 on white); dark keeps Apple's #FFCC00.
    static let yellow = adaptiveColor(
        light: NSColor(red: 154/255, green: 103/255, blue: 0/255, alpha: 1),
        dark: NSColor(red: 255/255, green: 204/255, blue: 0/255, alpha: 1)
    )

    /// Orange - High usage (75-90%). Light variant is Primer's "severe"
    /// orange (#BC4C00, ~5:1 on white); dark keeps the original #E67E00.
    static let orange = adaptiveColor(
        light: NSColor(red: 188/255, green: 76/255, blue: 0/255, alpha: 1),
        dark: NSColor(red: 230/255, green: 126/255, blue: 0/255, alpha: 1)
    )

    /// Red - Critical usage (90-100%). Light variant is Primer's "danger"
    /// red (#CF222E, ~5.4:1 on white); dark keeps Apple's #FF3B30.
    static let red = adaptiveColor(
        light: NSColor(red: 207/255, green: 34/255, blue: 46/255, alpha: 1),
        dark: NSColor(red: 255/255, green: 59/255, blue: 48/255, alpha: 1)
    )

    // MARK: - UI Colors

    /// Primary accent color
    static let accent = Color(red: 175/255, green: 82/255, blue: 222/255)  // #AF52DE - Purple (Claude brand)

    /// Background color for cards (deprecated - use .regularMaterial instead)
    @available(*, deprecated, message: "Use .regularMaterial for glass effect")
    static let cardBackground = Color(nsColor: .controlBackgroundColor)

    /// Secondary text color
    static let secondaryText = Color(nsColor: .secondaryLabelColor)

    /// Border color for card outlines and progress track backgrounds.
    /// `.separatorColor` is tuned by AppKit to stay visible on both light and
    /// dark window backgrounds — a fixed opacity on `.primary` reads far
    /// fainter on white than on near-black, since equal alpha steps aren't
    /// equally visible in both directions.
    static let cardBorder = Color(nsColor: .separatorColor)

    // MARK: - Glass Effect Colors

    /// Subtle overlay for glass effect
    static let glassOverlay = Color.white.opacity(0.05)

    /// Border color for glass cards
    static let glassBorder = Color.white.opacity(0.1)

    // MARK: - Methods

    /// Returns the appropriate color based on usage percentage
    /// - Parameter usage: Usage percentage (0-100)
    /// - Returns: Color corresponding to the usage level
    static func colorForUsage(_ usage: Double) -> Color {
        switch usage {
        case 0..<50:
            return green
        case 50..<75:
            return yellow
        case 75..<90:
            return orange
        default:
            return red
        }
    }

    /// Returns gradient colors for usage visualization
    /// - Parameter usage: Usage percentage (0-100)
    /// - Returns: Array of colors for gradient
    static func gradientForUsage(_ usage: Double) -> [Color] {
        let primaryColor = colorForUsage(usage)
        return [primaryColor.opacity(0.8), primaryColor]
    }

    /// Returns NSColor for AppKit compatibility
    static func nsColorForUsage(_ usage: Double) -> NSColor {
        return NSColor(colorForUsage(usage))
    }

    // MARK: - Forecast Colors

    /// Maps a time-aware pace status to its display colour. This is the primary
    /// colour rule: the hue answers "at this rate, will the window run out
    /// before it resets?" rather than keying off a static percentage.
    static func color(for status: WindowForecast.PaceStatus) -> Color {
        switch status {
        case .safe:     return green
        case .watch:    return yellow
        case .warning:  return orange
        case .critical: return red
        }
    }

    /// Forecast-driven colour, falling back to the plain percentage colour when
    /// no forecast is available (no reset time, or too early in the window).
    static func color(for forecast: WindowForecast?, fallbackUsage: Double) -> Color {
        if let forecast { return color(for: forecast.status) }
        return colorForUsage(fallbackUsage)
    }

    /// NSColor variant of `color(for:fallbackUsage:)` for AppKit (menu bar) use.
    static func nsColor(for forecast: WindowForecast?, fallbackUsage: Double) -> NSColor {
        return NSColor(color(for: forecast, fallbackUsage: fallbackUsage))
    }
}

// MARK: - Color Extensions for Theme

extension Color {
    static let usageGreen = ColorTheme.green
    static let usageYellow = ColorTheme.yellow
    static let usageOrange = ColorTheme.orange
    static let usageRed = ColorTheme.red
    static let claudeAccent = ColorTheme.accent
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 10) {
            Circle().fill(ColorTheme.green).frame(width: 40, height: 40)
            Text("Green (0-50%)")
        }
        HStack(spacing: 10) {
            Circle().fill(ColorTheme.yellow).frame(width: 40, height: 40)
            Text("Yellow (50-75%)")
        }
        HStack(spacing: 10) {
            Circle().fill(ColorTheme.orange).frame(width: 40, height: 40)
            Text("Orange (75-90%)")
        }
        HStack(spacing: 10) {
            Circle().fill(ColorTheme.red).frame(width: 40, height: 40)
            Text("Red (90-100%)")
        }
    }
    .padding()
}
