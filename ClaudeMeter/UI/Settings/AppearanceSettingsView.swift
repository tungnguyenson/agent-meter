//
//  AppearanceSettingsView.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI

// MARK: - MenuBarHex

enum MenuBarHex {
    /// Normalizes user hex input to canonical "#RRGGBB" (uppercase), or nil if invalid.
    /// Accepts optional leading '#', surrounding whitespace; requires exactly 6 hex digits.
    static func normalize(_ input: String) -> String? {
        let cleaned = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()
        guard cleaned.count == 6, cleaned.allSatisfy(\.isHexDigit) else { return nil }
        return "#\(cleaned)"
    }
}

private let menuBarColorPresets: [String] = [
    "#FFFFFF", "#B3B3B3", "#000000", "#FF3B30",
    "#FF9500", "#34C759", "#0A84FF", "#AF52DE",
]

// MARK: - ColorSwatchField

private struct ColorSwatchField: View {
    let title: String
    @Binding var hex: String

    @State private var draftHex: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
                TextField("#RRGGBB", text: $draftHex)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(commitDraft)
            }

            HStack(spacing: 8) {
                ForEach(menuBarColorPresets, id: \.self) { preset in
                    let isSelected = MenuBarHex.normalize(hex) == preset
                    Circle()
                        .fill(Color(hex: preset))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle().stroke(
                                isSelected ? Color.accentColor : Color.primary.opacity(0.15),
                                lineWidth: isSelected ? 2 : 0.5
                            )
                        )
                        .contentShape(Circle())
                        .help(preset)
                        .onTapGesture {
                            hex = preset
                            draftHex = preset
                        }
                }
            }
        }
        .onAppear {
            draftHex = hex
        }
    }

    private func commitDraft() {
        if let normalized = MenuBarHex.normalize(draftHex) {
            hex = normalized
            draftHex = normalized
        } else {
            draftHex = hex
        }
    }
}

// MARK: - Appearance Settings
struct AppearanceSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        SettingsTabContainer {
            Form {
                Section(header: Text("Menu Bar Display")) {
                    Picker("Display Mode", selection: $appState.settings.displayMode) {
                        ForEach(DisplayMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    if appState.settings.displayMode == .detailed {
                        Picker("Detailed Label", selection: $appState.settings.detailedModeStyle) {
                            ForEach(DetailedModeStyle.allCases, id: \.self) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                        .pickerStyle(.radioGroup)
                    }
                }
                .background(ScrollBarHider())

                Section(header: Text("Color Scheme")) {
                    Picker("Theme", selection: $appState.settings.colorScheme) {
                        ForEach(AppColorScheme.allCases, id: \.self) { scheme in
                            Text(scheme.rawValue).tag(scheme)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if appState.settings.displayMode == .detailed {
                    Section(header: Text("Menu Bar Colors")) {
                        Toggle("Custom icon & text colors", isOn: $appState.settings.customMenuBarColorsEnabled)

                        if appState.settings.customMenuBarColorsEnabled {
                            ColorSwatchField(title: "Icon color", hex: $appState.settings.menuBarIconColorHex)
                            ColorSwatchField(title: "Text color", hex: $appState.settings.menuBarTextColorHex)
                        }

                        Text("Applies to Detailed mode. The percentage still changes color by usage level.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollIndicators(.hidden)
        }
    }
}
