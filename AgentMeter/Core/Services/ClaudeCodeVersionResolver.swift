//
//  ClaudeCodeVersionResolver.swift
//  AgentMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation

/// Resolves the version of the locally installed Claude Code CLI so the app can
/// send a `User-Agent` that matches the real client (e.g. `claude-code/2.1.201`)
/// instead of a hardcoded value that drifts out of date and risks rejection by
/// the OAuth usage endpoint.
///
/// Detection is PATH-independent (a menu-bar app does not inherit the shell
/// PATH). Strategies are tried fastest-first and the first valid semantic
/// version wins:
///   1. Basename of the `~/.local/bin/claude` symlink target (native install).
///   2. Highest version folder in `~/.local/share/claude/versions/` (native).
///   3. `version_to` from `~/.claude/.last-update-result.json` (native).
///   4. `claude --version` from known binary locations (npm / Homebrew / native).
///
/// If every strategy fails, `userAgent` falls back to `Constants.API.userAgent`.
/// The result is resolved once and cached for the app's lifetime; a CLI that
/// self-updates mid-session is picked up on the next launch.
final class ClaudeCodeVersionResolver {

    // MARK: - Shared Instance

    static let shared = ClaudeCodeVersionResolver()

    // MARK: - Dependencies

    private let homeDirectory: URL
    private let fileManager: FileManager
    /// Runs `<path> --version` and returns its stdout, or nil on failure.
    /// Injectable so tests never launch a real process.
    private let commandRunner: (String) -> String?

    // MARK: - Cache

    private let lock = NSLock()
    private var hasResolved = false
    private var cachedVersion: String?

    // MARK: - Init

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        commandRunner: @escaping (String) -> String? = ClaudeCodeVersionResolver.runVersionCommand
    ) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        self.commandRunner = commandRunner
    }

    // MARK: - Public API

    /// `User-Agent` header value reflecting the installed CLI, or the pinned
    /// fallback when the version cannot be detected.
    var userAgent: String {
        guard let version = resolvedVersion else { return Constants.API.userAgent }
        return "\(Constants.API.clientName)/\(version)"
    }

    /// The detected Claude Code version (e.g. `"2.1.201"`), or nil if none of
    /// the detection strategies succeeded. Resolved once, then cached.
    var resolvedVersion: String? {
        lock.lock()
        defer { lock.unlock() }
        if !hasResolved {
            cachedVersion = detectVersion()
            hasResolved = true
        }
        return cachedVersion
    }

    // MARK: - Detection Strategies

    private func detectVersion() -> String? {
        return versionFromLauncherSymlink()
            ?? versionFromVersionsDirectory()
            ?? versionFromLastUpdateResult()
            ?? versionFromVersionCommand()
    }

    /// Strategy 1: `~/.local/bin/claude` is a symlink to `.../versions/<version>`.
    private func versionFromLauncherSymlink() -> String? {
        let launcher = homeDirectory.appendingPathComponent(".local/bin/claude").path
        guard let target = try? fileManager.destinationOfSymbolicLink(atPath: launcher) else {
            return nil
        }
        return Self.extractVersion(from: (target as NSString).lastPathComponent)
    }

    /// Strategy 2: highest version folder under `~/.local/share/claude/versions/`.
    private func versionFromVersionsDirectory() -> String? {
        let versionsDir = homeDirectory.appendingPathComponent(".local/share/claude/versions").path
        guard let entries = try? fileManager.contentsOfDirectory(atPath: versionsDir) else {
            return nil
        }
        return entries
            .compactMap { Self.extractVersion(from: $0) }
            .max { $0.compare($1, options: .numeric) == .orderedAscending }
    }

    /// Strategy 3: `version_to` recorded by the native auto-updater.
    private func versionFromLastUpdateResult() -> String? {
        let resultURL = homeDirectory.appendingPathComponent(".claude/.last-update-result.json")
        guard let data = try? Data(contentsOf: resultURL),
              let result = try? JSONDecoder().decode(LastUpdateResult.self, from: data),
              let version = result.versionTo else {
            return nil
        }
        return Self.extractVersion(from: version)
    }

    /// Strategy 4: run `claude --version` from the first known executable path.
    private func versionFromVersionCommand() -> String? {
        for path in candidateBinaryPaths() {
            guard let output = commandRunner(path) else { continue }
            if let version = Self.extractVersion(from: output) {
                return version
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func candidateBinaryPaths() -> [String] {
        return [
            homeDirectory.appendingPathComponent(".local/bin/claude").path,
            homeDirectory.appendingPathComponent(".claude/local/claude").path,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude"
        ]
    }

    /// Extracts the first `major.minor.patch` sequence from arbitrary text
    /// (e.g. `"2.1.201 (Claude Code)"` -> `"2.1.201"`). Returns nil if absent.
    static func extractVersion(from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\b(\d+\.\d+\.\d+)\b"#) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let versionRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[versionRange])
    }

    /// Default `commandRunner`: launches `<path> --version` and returns stdout.
    static func runVersionCommand(path: String) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        return String(data: outputData, encoding: .utf8)
    }

    // MARK: - Native Auto-Updater Record

    private struct LastUpdateResult: Decodable {
        let versionTo: String?

        enum CodingKeys: String, CodingKey {
            case versionTo = "version_to"
        }
    }
}
