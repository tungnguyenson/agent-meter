//
//  MenuBarCountdownFormatterTests.swift
//  ClaudeMeterTests
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import XCTest
@testable import ClaudeMeter

final class MenuBarCountdownFormatterTests: XCTestCase {
    func test_daysHours_whenLessThanOneHour_returnsMinutes() {
        XCTAssertEqual(
            MenuBarCountdownFormatter.label(
                remaining: 26 * .minute,
                units: .daysHours
            ),
            "26m"
        )
    }

    func test_daysHours_atHourBoundary_returnsOneHour() {
        XCTAssertEqual(
            MenuBarCountdownFormatter.label(
                remaining: .hour,
                units: .daysHours
            ),
            "1h"
        )
    }

    func test_daysHours_justBeforeOneHour_returnsFiftyNineMinutes() {
        XCTAssertEqual(
            MenuBarCountdownFormatter.label(
                remaining: .hour - 1,
                units: .daysHours
            ),
            "59m"
        )
    }

    func test_daysHours_whenMoreThanOneDay_preservesDaysAndHours() {
        XCTAssertEqual(
            MenuBarCountdownFormatter.label(
                remaining: 25 * .hour,
                units: .daysHours
            ),
            "1d 1h"
        )
    }

    func test_hoursMinutes_preservesHoursAndMinutes() {
        XCTAssertEqual(
            MenuBarCountdownFormatter.label(
                remaining: (3 * .hour) + (42 * .minute),
                units: .hoursMinutes
            ),
            "3h 42m"
        )
    }

    func test_label_whenRemainingIsNotPositive_returnsNil() {
        XCTAssertNil(
            MenuBarCountdownFormatter.label(
                remaining: 0,
                units: .daysHours
            )
        )
    }
}
