//
//  WindowForecast.swift
//  AgentMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation

/// A time-aware forecast for a single usage window.
///
/// Raw utilization on its own can't answer the question that actually matters —
/// *"at this rate, will I run out before the window resets?"* 50% one hour into
/// a five-hour window is on pace to blow past the cap; 50% four hours in is
/// comfortable. This value type projects the current **average pace** (usage
/// since the window opened) forward to the reset time and classifies the result.
struct WindowForecast: Equatable {

    // MARK: - Pace Status

    /// Where the current pace lands the window by reset time.
    enum PaceStatus: Equatable {
        case safe      // finishes comfortably under the cap
        case watch     // finishes close to the cap
        case warning   // will hit the cap, but not until late in the window
        case critical  // will hit the cap soon, or is already nearly out
    }

    // MARK: - Properties

    /// Current utilization, 0–100.
    let utilization: Double
    /// Fraction of the window that has elapsed, 0–1.
    let elapsedFraction: Double
    /// Seconds remaining until the window resets.
    let timeToReset: TimeInterval
    /// Utilization (%) projected at reset if the current average pace holds.
    /// Not clamped — values above 100 signal how far past the cap the pace runs.
    let projectedUsage: Double
    /// True when the projected usage reaches the 100% cap before reset.
    let willExhaust: Bool
    /// Seconds until utilization is projected to hit 100% at the current pace.
    /// `nil` when the window is not on track to exhaust.
    let timeToExhaust: TimeInterval?
    /// Classified pace status driving the display colour.
    let status: PaceStatus
}

// MARK: - Construction

extension WindowForecast {
    /// Builds a forecast from a window's utilization and reset time using the
    /// average pace since the window opened.
    ///
    /// Returns `nil` when there isn't enough signal to forecast — no reset time,
    /// the window has already reset, or it is too early in the window for the
    /// projection to be meaningful — so callers fall back to a plain percentage.
    static func make(
        utilization: Double,
        resetsAt: Date?,
        duration: TimeInterval,
        now: Date = Date()
    ) -> WindowForecast? {
        guard let resetsAt, duration > 0 else { return nil }

        let timeToReset = resetsAt.timeIntervalSince(now)
        guard timeToReset > 0 else { return nil }   // already reset

        let elapsed = duration - timeToReset
        guard elapsed > 0 else { return nil }       // clock skew / not yet started
        let elapsedFraction = min(max(elapsed / duration, 0), 1)

        // Too early: a couple of calls right after reset would read as "will run
        // out" under naive extrapolation. Defer to the percentage fallback.
        guard elapsedFraction >= Constants.Window.minElapsedFractionForForecast else {
            return nil
        }

        let usage = max(utilization, 0)
        let projectedUsage = usage / elapsedFraction
        let willExhaust = projectedUsage >= 100

        // Time until utilization reaches 100% at the current average rate:
        // rate = usage / elapsed (%/s), remaining budget = 100 − usage.
        // Clamped at 0 so an already-over-cap window reads as "out now".
        let timeToExhaust: TimeInterval?
        if willExhaust, usage > 0 {
            timeToExhaust = max(0, elapsed * (100 - usage) / usage)
        } else {
            timeToExhaust = nil
        }

        let status = Self.classify(
            usage: usage,
            projectedUsage: projectedUsage,
            willExhaust: willExhaust,
            timeToExhaust: timeToExhaust,
            timeToReset: timeToReset
        )

        return WindowForecast(
            utilization: usage,
            elapsedFraction: elapsedFraction,
            timeToReset: timeToReset,
            projectedUsage: projectedUsage,
            willExhaust: willExhaust,
            timeToExhaust: timeToExhaust,
            status: status
        )
    }

    // MARK: - Classification

    private static func classify(
        usage: Double,
        projectedUsage: Double,
        willExhaust: Bool,
        timeToExhaust: TimeInterval?,
        timeToReset: TimeInterval
    ) -> PaceStatus {
        // Nearly out right now — always the loudest state, regardless of pace.
        if usage >= Constants.Window.nearCapThreshold { return .critical }

        guard willExhaust else {
            // On track to finish under the cap.
            return projectedUsage >= Constants.Window.projectedWatchThreshold ? .watch : .safe
        }

        // Will hit the cap before reset — how soon?
        guard let timeToExhaust, timeToReset > 0 else { return .warning }
        let exhaustFraction = timeToExhaust / timeToReset  // 0 = now, →1 = just before reset
        return exhaustFraction < Constants.Window.earlyExhaustRatio ? .critical : .warning
    }
}
