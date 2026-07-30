//
//  DebugLogView.swift
//  AgentMeter
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

    private enum LogStatus {
        case pending
        case success
        case error

        var label: String {
            switch self {
            case .pending: return "PENDING"
            case .success: return "SUCCESS"
            case .error: return "ERROR"
            }
        }

        var color: Color {
            switch self {
            case .pending: return .secondary
            case .success: return .green
            case .error: return .red
            }
        }
    }

    private struct LogRow: Identifiable {
        let id: UUID
        var timestamp: Date
        let providerID: ProviderID?
        let apiCall: String
        var status: LogStatus

        var providerLabel: String {
            providerID?.shortName ?? "Unknown"
        }

        var transportSymbol: String {
            providerID?.debugTransportSymbol ?? "questionmark.circle"
        }
    }

    private var logRows: [LogRow] {
        var rows: [LogRow] = []

        for entry in logger.entries {
            guard let apiCall = apiCall(from: entry.message) else { continue }

            switch entry.category {
            case .request, .fallback:
                rows.append(LogRow(
                    id: entry.id,
                    timestamp: entry.timestamp,
                    providerID: entry.providerID,
                    apiCall: apiCall,
                    status: .pending
                ))
            case .response, .error:
                if let index = rows.indices.reversed().first(where: {
                    rows[$0].apiCall == apiCall
                        && rows[$0].providerID == entry.providerID
                        && rows[$0].status == .pending
                }) {
                    rows[index].timestamp = entry.timestamp
                    rows[index].status = entry.category == .response ? .success : .error
                } else {
                    rows.append(LogRow(
                        id: entry.id,
                        timestamp: entry.timestamp,
                        providerID: entry.providerID,
                        apiCall: apiCall,
                        status: entry.category == .response ? .success : .error
                    ))
                }
            case .cache, .info:
                continue
            }
        }

        return rows
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            if logRows.isEmpty {
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
                ForEach(logRows.reversed()) { row in
                    logEntryRow(row)
                }
            }
            .padding(.horizontal)
        }
    }

    private func logEntryRow(_ row: LogRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(Self.timeFormatter.string(from: row.timestamp))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                Text(row.providerLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(4)

                Spacer(minLength: 0)

                Text(row.status.label)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(row.status.color)
            }

            HStack(alignment: .top, spacing: 5) {
                Image(systemName: row.transportSymbol)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.7))

                Text(row.apiCall)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
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
            Text("\(logRows.count) calls")
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

    private func apiCall(from message: String) -> String? {
        guard message.hasPrefix("API: ") else { return nil }

        let call = String(message.dropFirst(5))
            .replacingOccurrences(of: " SUCCESS", with: "")
            .replacingOccurrences(of: " FAILED", with: "")
        return call.isEmpty ? nil : call
    }

    private func copyAllLogs() {
        let text = logRows.map { row in
            let time = Self.timeFormatter.string(from: row.timestamp)
            return "[\(time)] [\(row.providerLabel)] \(row.apiCall) \(row.status.label)"
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
