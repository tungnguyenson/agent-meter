//
//  AppearanceSettingsView.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI

// MARK: - Appearance Settings
struct AppearanceSettingsView: View {
    @ObservedObject var appState: AppState

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
                            ColorPicker("Icon color", selection: iconColorBinding, supportsOpacity: false)
                            ColorPicker("Text color", selection: textColorBinding, supportsOpacity: false)
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
