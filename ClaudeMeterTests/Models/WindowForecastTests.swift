//
//  WindowForecastTests.swift
//  ClaudeMeterTests
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import XCTest
@testable import ClaudeMeter

final class WindowForecastTests: XCTestCase {

    private let fiveHour = Constants.Window.fiveHourDuration

    /// A reset time that leaves `fraction` of the window still to run.
    private func resetsAt(remainingFraction fraction: Double, from now: Date) -> Date {
        now.addingTimeInterval(fiveHour * fraction)
    }

    // MARK: - Guards (fall back to plain percentage)

    func testNilResetsAtReturnsNil() {
        XCTAssertNil(WindowForecast.make(utilization: 50, resetsAt: nil, duration: fiveHour, now: Date()))
    }

    func testAlreadyResetReturnsNil() {
        let now = Date()
        let past = now.addingTimeInterval(-10)
        XCTAssertNil(WindowForecast.make(utilization: 50, resetsAt: past, duration: fiveHour, now: now))
    }

    func testZeroDurationReturnsNil() {
        let now = Date()
        XCTAssertNil(WindowForecast.make(utilization: 50, resetsAt: now.addingTimeInterval(3600), duration: 0, now: now))
    }

    func testTooEarlyInWindowReturnsNil() {
        let now = Date()
        // Only 1% of the window elapsed — below the minimum forecast fraction.
        let reset = resetsAt(remainingFraction: 0.99, from: now)
        XCTAssertNil(WindowForecast.make(utilization: 5, resetsAt: reset, duration: fiveHour, now: now))
    }

    // MARK: - The core reframe: same % → opposite meaning

    func testHalfUsedEarlyProjectsExhaustionAndIsCritical() throws {
        let now = Date()
        // 20% elapsed, 50% used → projected 250%, exhausts well before reset.
        let reset = resetsAt(remainingFraction: 0.8, from: now)
        let f = try XCTUnwrap(WindowForecast.make(utilization: 50, resetsAt: reset, duration: fiveHour, now: now))

        XCTAssertEqual(f.elapsedFraction, 0.2, accuracy: 0.0001)
        XCTAssertEqual(f.projectedUsage, 250, accuracy: 0.5)
        XCTAssertTrue(f.willExhaust)
        // rate = 50% over 1h → remaining 50% takes another 1h.
        XCTAssertEqual(try XCTUnwrap(f.timeToExhaust), 3600, accuracy: 1)
        XCTAssertEqual(f.status, .critical)
    }

    func testHalfUsedLateIsSafe() throws {
        let now = Date()
        // 80% elapsed, 50% used → projected 62.5%, never exhausts.
        let reset = resetsAt(remainingFraction: 0.2, from: now)
        let f = try XCTUnwrap(WindowForecast.make(utilization: 50, resetsAt: reset, duration: fiveHour, now: now))

        XCTAssertEqual(f.projectedUsage, 62.5, accuracy: 0.5)
        XCTAssertFalse(f.willExhaust)
        XCTAssertNil(f.timeToExhaust)
        XCTAssertEqual(f.status, .safe)
    }

    // MARK: - Status bands

    func testProjectedNearCapIsWatch() throws {
        let now = Date()
        // 80% elapsed, 76% used → projected 95% (< 100, ≥ 90) → watch.
        let reset = resetsAt(remainingFraction: 0.2, from: now)
        let f = try XCTUnwrap(WindowForecast.make(utilization: 76, resetsAt: reset, duration: fiveHour, now: now))

        XCTAssertEqual(f.projectedUsage, 95, accuracy: 0.5)
        XCTAssertFalse(f.willExhaust)
        XCTAssertEqual(f.status, .watch)
    }

    func testExhaustLateIsWarning() throws {
        let now = Date()
        // 50% elapsed, 55% used → projected 110%, runs out only near the end.
        let reset = resetsAt(remainingFraction: 0.5, from: now)
        let f = try XCTUnwrap(WindowForecast.make(utilization: 55, resetsAt: reset, duration: fiveHour, now: now))

        XCTAssertTrue(f.willExhaust)
        // eta/remaining ≈ 0.82 ≥ 0.5 → warning, not critical.
        XCTAssertEqual(f.status, .warning)
    }

    func testExhaustEarlyIsCritical() throws {
        let now = Date()
        // 50% elapsed, 80% used → projected 160%, runs out early.
        let reset = resetsAt(remainingFraction: 0.5, from: now)
        let f = try XCTUnwrap(WindowForecast.make(utilization: 80, resetsAt: reset, duration: fiveHour, now: now))

        XCTAssertTrue(f.willExhaust)
        // eta/remaining = 0.25 < 0.5 → critical.
        XCTAssertEqual(f.status, .critical)
    }

    func testNearCapOverrideIsCriticalEvenWhenNotExhausting() throws {
        let now = Date()
        // 99% elapsed, 96% used → projected < 100 (won't exhaust) but the near-cap
        // override still fires because you're nearly out right now.
        let reset = resetsAt(remainingFraction: 0.01, from: now)
        let f = try XCTUnwrap(WindowForecast.make(utilization: 96, resetsAt: reset, duration: fiveHour, now: now))

        XCTAssertFalse(f.willExhaust)
        XCTAssertEqual(f.status, .critical)
    }

    func testAlreadyOverCapClampsExhaustToZero() throws {
        let now = Date()
        let reset = resetsAt(remainingFraction: 0.2, from: now)
        let f = try XCTUnwrap(WindowForecast.make(utilization: 105, resetsAt: reset, duration: fiveHour, now: now))

        XCTAssertTrue(f.willExhaust)
        XCTAssertEqual(try XCTUnwrap(f.timeToExhaust), 0, accuracy: 0.0001)
        XCTAssertEqual(f.status, .critical)
    }
}
