//
//  DebugLogView.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI

struct DebugLogView: View {
    @ObservedObject private var logger = DebugLogger.shared
    var onDismiss: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            headerView

            if logger.entries.isEmpty {
                emptyStateView
            } else {
                logList
            }

            footerView
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack {
            Button(action: {
                if let onDismiss = onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("API Logs")
                .font(.headline)

            Spacer()

            Button(action: {
                logger.clear()
            }) {
                Text("Clear")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .disabled(logger.entries.isEmpty)
        }
        .padding(.horizontal)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Log List
    private var logList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(logger.entries.reversed()) { entry in
                    logEntryRow(entry)
                }
            }
            .padding(.horizontal)
        }
    }

    private func logEntryRow(_ entry: DebugLogEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.category.icon)
                .foregroundColor(colorFor(entry.category))
                .font(.system(size: 14))
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.category.rawValue)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(colorFor(entry.category).opacity(0.1))
                        .foregroundColor(colorFor(entry.category))
                        .cornerRadius(3)

                    Spacer()

                    Text(Self.timeFormatter.string(from: entry.timestamp))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Text(entry.message)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)

                if let detail = entry.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(6)
        .padding(.vertical, 2)
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No logs yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("API fetch calls will appear here")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - Footer
    private var footerView: some View {
        HStack {
            Text("\(logger.entries.count) entries")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Spacer()
            Button("Copy All") {
                copyAllLogs()
            }
            .font(.system(size: 10))
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05))
    }

    private func colorFor(_ category: DebugLogEntry.Category) -> Color {
        switch category {
        case .request: return .blue
        case .response: return .green
        case .fallback: return .orange
        case .cache: return .purple
        case .error: return .red
        case .info: return .secondary
        }
    }

    private func copyAllLogs() {
        let text = logger.entries.map { entry in
            let time = Self.timeFormatter.string(from: entry.timestamp)
            var line = "[\(time)] [\(entry.category.rawValue)] \(entry.message)"
            if let detail = entry.detail {
                line += "\n  \(detail)"
            }
            return line
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

