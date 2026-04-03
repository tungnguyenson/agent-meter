//
//  DebugLogger.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation

struct DebugLogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let category: Category
    let message: String
    let detail: String?

    enum Category: String, Codable {
        case request = "REQ"
        case response = "RES"
        case fallback = "FALLBACK"
        case cache = "CACHE"
        case error = "ERR"
        case info = "INFO"

        var icon: String {
            switch self {
            case .request: return "arrow.up.circle"
            case .response: return "arrow.down.circle"
            case .fallback: return "arrow.triangle.2.circlepath"
            case .cache: return "cylinder"
            case .error: return "xmark.circle"
            case .info: return "info.circle"
            }
        }
    }

    init(id: UUID = UUID(), timestamp: Date, category: Category, message: String, detail: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.message = message
        self.detail = detail
    }
}

@MainActor
class DebugLogger: ObservableObject {
    static let shared = DebugLogger()

    @Published private(set) var entries: [DebugLogEntry] = []
    private let maxEntries = Constants.Logging.maxEntries
    private let fileManager = FileManager.default
    private let logDirectory: URL
    private let logFile = Constants.Logging.filename

    private init() {
        // Get log directory with safe fallback
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        logDirectory = caches.appendingPathComponent(Constants.Logging.directoryName, isDirectory: true)

        // Create log directory if needed
        do {
            try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        } catch {
            print("DebugLogger: Failed to create log directory - \(error)")
        }

        // Load existing logs
        loadFromDisk()
    }

    func log(_ category: DebugLogEntry.Category, _ message: String, detail: String? = nil) {
        let entry = DebugLogEntry(timestamp: Date(), category: category, message: message, detail: detail)
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        print("[\(category.rawValue)] \(message)")

        // Persist
        saveToDisk()
    }

    func clear() {
        entries.removeAll()
        saveToDisk()
    }

    private func saveToDisk() {
        let fileURL = logDirectory.appendingPathComponent(logFile)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            try data.write(to: fileURL)
        } catch {
            print("DebugLogger: Failed to save logs - \(error)")
        }
    }

    private func loadFromDisk() {
        let fileURL = logDirectory.appendingPathComponent(logFile)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            self.entries = try decoder.decode([DebugLogEntry].self, from: data)
        } catch {
            print("DebugLogger: Failed to load logs - \(error)")
        }
    }
}

