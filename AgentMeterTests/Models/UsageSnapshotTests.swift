//
//  UsageSnapshotTests.swift
//  AgentMeterTests
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import XCTest
@testable import AgentMeter

/// `pinnedPercentageMetrics` feeds both compact surfaces — the menu bar title
/// and the all-providers overview — so a change here shifts what both show.
final class UsageSnapshotTests: XCTestCase {

    // MARK: - Fixtures

    private func percentMetric(id: String, percent: Double) -> UsageMetric {
        UsageMetric(
            id: id,
            title: id,
            shortLabel: id,
            category: .rateLimit,
            usedPercent: percent,
            resetsAt: Date().addingTimeInterval(3600),
            windowDuration: Constants.Window.fiveHourDuration
        )
    }

    private func creditsMetric(id: String) -> UsageMetric {
        UsageMetric(
            id: id,
            title: id,
            shortLabel: id,
            category: .credits,
            usedValue: 12,
            unit: "credits"
        )
    }

    private func snapshot(metrics: [UsageMetric]) -> UsageSnapshot {
        UsageSnapshot(
            providerID: .claudeCode,
            fetchedAt: Date(),
            metrics: metrics
        )
    }

    // MARK: - Pin Ordering

    func testPinnedMetricsAreReturnedInPinOrderNotResponseOrder() {
        let subject = snapshot(metrics: [
            percentMetric(id: "a", percent: 10),
            percentMetric(id: "b", percent: 20),
            percentMetric(id: "c", percent: 30)
        ])

        let result = subject.pinnedPercentageMetrics(pinnedIDs: ["c", "a"])

        XCTAssertEqual(result.map(\.id), ["c", "a"])
    }

    func testResultIsCappedAtTheLimitEvenWithMorePins() {
        let subject = snapshot(metrics: [
            percentMetric(id: "a", percent: 10),
            percentMetric(id: "b", percent: 20),
            percentMetric(id: "c", percent: 30)
        ])

        let result = subject.pinnedPercentageMetrics(pinnedIDs: ["a", "b", "c"])

        XCTAssertEqual(result.count, Constants.Overview.pinnedMetricLimit)
        XCTAssertEqual(result.map(\.id), ["a", "b"])
    }

    func testExplicitLimitOverridesTheDefault() {
        let subject = snapshot(metrics: [
            percentMetric(id: "a", percent: 10),
            percentMetric(id: "b", percent: 20)
        ])

        let result = subject.pinnedPercentageMetrics(pinnedIDs: ["a", "b"], limit: 1)

        XCTAssertEqual(result.map(\.id), ["a"])
    }

    // MARK: - Backfill

    func testUnknownPinsAreBackfilledFromRemainingPercentageMetrics() {
        let subject = snapshot(metrics: [
            percentMetric(id: "a", percent: 10),
            percentMetric(id: "b", percent: 20)
        ])

        let result = subject.pinnedPercentageMetrics(pinnedIDs: ["gone"])

        XCTAssertEqual(result.map(\.id), ["a", "b"])
    }

    func testBackfillNeverDuplicatesAnAlreadyPinnedMetric() {
        let subject = snapshot(metrics: [
            percentMetric(id: "a", percent: 10),
            percentMetric(id: "b", percent: 20)
        ])

        let result = subject.pinnedPercentageMetrics(pinnedIDs: ["b"])

        XCTAssertEqual(result.map(\.id), ["b", "a"])
    }

    // MARK: - Percentage Filtering

    func testPinnedMetricWithoutAPercentageIsSkipped() {
        let subject = snapshot(metrics: [
            creditsMetric(id: "credits"),
            percentMetric(id: "a", percent: 10)
        ])

        let result = subject.pinnedPercentageMetrics(pinnedIDs: ["credits", "a"])

        XCTAssertEqual(result.map(\.id), ["a"])
    }

    func testSnapshotWithNoPercentageMetricsReturnsEmpty() {
        let subject = snapshot(metrics: [creditsMetric(id: "credits")])

        XCTAssertTrue(subject.pinnedPercentageMetrics(pinnedIDs: ["credits"]).isEmpty)
    }
}
