//
//  ClaudeCodeVersionResolverTests.swift
//  ClaudeMeterTests
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import XCTest
@testable import ClaudeMeter

final class ClaudeCodeVersionResolverTests: XCTestCase {

    // MARK: - Properties

    private var tempHome: URL!
    private let fileManager = FileManager.default

    // MARK: - Setup / Teardown

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempHome = fileManager.temporaryDirectory
            .appendingPathComponent("ClaudeMeterTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempHome, fileManager.fileExists(atPath: tempHome.path) {
            try fileManager.removeItem(at: tempHome)
        }
        tempHome = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makeResolver(commandOutput: String? = nil) -> ClaudeCodeVersionResolver {
        ClaudeCodeVersionResolver(
            homeDirectory: tempHome,
            fileManager: fileManager,
            commandRunner: { _ in commandOutput }
        )
    }

    private func makeDirectory(_ relativePath: String) throws -> URL {
        let url = tempHome.appendingPathComponent(relativePath, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - extractVersion

    func testExtractVersion_fromCommandOutput() {
        XCTAssertEqual(ClaudeCodeVersionResolver.extractVersion(from: "2.1.201 (Claude Code)"), "2.1.201")
    }

    func testExtractVersion_fromBareVersion() {
        XCTAssertEqual(ClaudeCodeVersionResolver.extractVersion(from: "10.20.30"), "10.20.30")
    }

    func testExtractVersion_returnsNilWhenNoSemver() {
        XCTAssertNil(ClaudeCodeVersionResolver.extractVersion(from: "not a version"))
        XCTAssertNil(ClaudeCodeVersionResolver.extractVersion(from: "1.2"))
    }

    // MARK: - Fallback

    func testUserAgent_fallsBackWhenNothingDetected() {
        let resolver = makeResolver(commandOutput: nil)
        XCTAssertNil(resolver.resolvedVersion)
        XCTAssertEqual(resolver.userAgent, Constants.API.userAgent)
    }

    // MARK: - Strategy 1: launcher symlink

    func testResolvesFromLauncherSymlink() throws {
        let versionsDir = try makeDirectory(".local/share/claude/versions")
        let binDir = try makeDirectory(".local/bin")
        let target = versionsDir.appendingPathComponent("3.2.1")
        fileManager.createFile(atPath: target.path, contents: Data())
        try fileManager.createSymbolicLink(
            atPath: binDir.appendingPathComponent("claude").path,
            withDestinationPath: target.path
        )

        let resolver = makeResolver()
        XCTAssertEqual(resolver.resolvedVersion, "3.2.1")
        XCTAssertEqual(resolver.userAgent, "claude-code/3.2.1")
    }

    // MARK: - Strategy 2: versions directory (numeric ordering)

    func testResolvesHighestVersionNumerically() throws {
        let versionsDir = try makeDirectory(".local/share/claude/versions")
        for name in ["1.0.0", "2.0.9", "2.0.10", "backups"] {
            fileManager.createFile(atPath: versionsDir.appendingPathComponent(name).path, contents: Data())
        }

        let resolver = makeResolver()
        // 2.0.10 must beat 2.0.9 — proves numeric (not lexicographic) comparison.
        XCTAssertEqual(resolver.resolvedVersion, "2.0.10")
    }

    // MARK: - Strategy 3: last-update-result.json

    func testResolvesFromLastUpdateResult() throws {
        _ = try makeDirectory(".claude")
        let json = #"{"version_from":"2.1.199","version_to":"2.1.205","outcome":"success"}"#
        let resultURL = tempHome.appendingPathComponent(".claude/.last-update-result.json")
        try json.data(using: .utf8)!.write(to: resultURL)

        let resolver = makeResolver()
        XCTAssertEqual(resolver.resolvedVersion, "2.1.205")
    }

    // MARK: - Strategy 4: version command

    func testResolvesFromVersionCommand() {
        // No filesystem markers exist, so the command runner is the only source.
        let resolver = makeResolver(commandOutput: "4.5.6 (Claude Code)")
        XCTAssertEqual(resolver.resolvedVersion, "4.5.6")
    }

    // MARK: - Precedence & caching

    func testSymlinkTakesPrecedenceOverCommand() throws {
        let versionsDir = try makeDirectory(".local/share/claude/versions")
        let binDir = try makeDirectory(".local/bin")
        let target = versionsDir.appendingPathComponent("3.2.1")
        fileManager.createFile(atPath: target.path, contents: Data())
        try fileManager.createSymbolicLink(
            atPath: binDir.appendingPathComponent("claude").path,
            withDestinationPath: target.path
        )

        let resolver = makeResolver(commandOutput: "9.9.9 (Claude Code)")
        XCTAssertEqual(resolver.resolvedVersion, "3.2.1")
    }

    func testResolutionIsCached() {
        var callCount = 0
        let resolver = ClaudeCodeVersionResolver(
            homeDirectory: tempHome,
            fileManager: fileManager,
            commandRunner: { _ in
                callCount += 1
                return "1.2.3 (Claude Code)"
            }
        )
        _ = resolver.resolvedVersion
        _ = resolver.resolvedVersion
        _ = resolver.userAgent
        // Detection runs once on the first read (the first candidate path yields
        // a version); later reads hit the cache instead of re-running the
        // command. Without caching, three reads would invoke it three times.
        XCTAssertEqual(callCount, 1)
    }
}
