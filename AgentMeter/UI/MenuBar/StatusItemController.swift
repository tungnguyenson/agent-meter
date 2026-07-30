//
//  StatusItemController.swift
//  AgentMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Cocoa
import SwiftUI
import Combine

enum MenuBarCountdownFormatter {
    enum Units {
        case hoursMinutes  // e.g. "3h 42m", "59m", "4h"
        case daysHours     // e.g. "3d 5h", "23h", "26m"
    }

    static func label(remaining: TimeInterval, units: Units) -> String? {
        guard remaining > 0 else { return nil }

        let totalMinutes = Int(remaining / 60)
        switch units {
        case .hoursMinutes:
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if hours == 0 { return "\(minutes)m" }
            if minutes == 0 { return "\(hours)h" }
            return "\(hours)h \(minutes)m"
        case .daysHours:
            if totalMinutes < 60 { return "\(totalMinutes)m" }

            let totalHours = totalMinutes / 60
            let days = totalHours / 24
            let hours = totalHours % 24
            if days == 0 { return "\(hours)h" }
            if hours == 0 { return "\(days)d" }
            return "\(days)d \(hours)h"
        }
    }
}

@MainActor
class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?

    // Progress icon configuration
    private let iconSize: CGFloat = 18

    init(appState: AppState) {
        self.appState = appState
        super.init()
        setupStatusItem()
        setupPopover()
        setupSubscriptions()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            if let image = NSImage(named: "AppLogo") {
                image.size = NSSize(width: 18, height: 18)
                button.image = image
            }
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    private func setupPopover() {
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 380, height: 560)
        pop.behavior = .transient
        // Delegate rather than the toggle methods: `.transient` popovers also
        // close on Escape and on dismissals AppKit handles itself, and
        // `PopoverView` resets its navigation off this flag.
        pop.delegate = self

        let popoverView = PopoverView(appState: appState)
        pop.contentViewController = NSHostingController(rootView: popoverView)
        popover = pop
    }

    private func setupSubscriptions() {
        // Update menu bar based on usage and display mode
        Publishers.CombineLatest(appState.$providerStates, appState.$settings)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] states, settings in
                let snapshot = states[settings.selectedProviderID]?.snapshot
                self?.updateMenuBarDisplay(with: snapshot, settings: settings)
            }
            .store(in: &cancellables)
    }

    // MARK: - Display Mode Rendering

    private func updateMenuBarDisplay(with snapshot: UsageSnapshot?, settings: AppSettings) {
        guard let button = statusItem?.button else { return }

        let metrics = pinnedMetrics(in: snapshot, settings: settings)
        let primaryMetric = metrics.first
        let primaryUsage = primaryMetric?.usedPercent ?? 0
        let primaryColor = ColorTheme.color(
            for: WindowForecast.make(
                utilization: primaryUsage,
                resetsAt: primaryMetric?.resetsAt,
                duration: primaryMetric?.windowDuration ?? 0
            ),
            fallbackUsage: primaryUsage
        )

        switch settings.displayMode {
        case .iconOnly:
            updateIconOnlyMode(button: button, usage: primaryUsage, color: primaryColor)
        case .compact:
            updateCompactMode(button: button, usage: primaryUsage, color: primaryColor)
        case .detailed:
            let palette = MenuBarColorPalette.resolve(from: settings)
            updateDetailedMode(
                button: button,
                providerID: settings.selectedProviderID,
                metrics: metrics,
                style: settings.detailedModeStyle,
                palette: palette
            )
        }
    }

    // MARK: - Icon Only Mode
    private func updateIconOnlyMode(button: NSStatusBarButton, usage: Double, color: Color) {
        button.title = ""
        button.image = createProgressIcon(progress: usage / 100.0, color: color)
    }

    // MARK: - Compact Mode (Icon + Percentage)
    private func updateCompactMode(button: NSStatusBarButton, usage: Double, color: Color) {
        button.image = createProgressIcon(progress: usage / 100.0, color: color)
        button.title = String(format: " %.0f%%", usage)
        button.imagePosition = .imageLeading
    }

    // MARK: - Detailed Mode

    private func pinnedMetrics(
        in snapshot: UsageSnapshot?,
        settings: AppSettings
    ) -> [UsageMetric] {
        guard let snapshot else { return [] }
        return snapshot.pinnedPercentageMetrics(
            pinnedIDs: settings.pinnedMetricIDsByProvider[snapshot.providerID] ?? []
        )
    }

    private func updateDetailedMode(
        button: NSStatusBarButton,
        providerID: ProviderID,
        metrics: [UsageMetric],
        style: DetailedModeStyle,
        palette: MenuBarColorPalette
    ) {
        button.image = nil
        guard !metrics.isEmpty else {
            button.attributedTitle = mutedTitle("--", color: palette.text)
            return
        }
        let title = NSMutableAttributedString()
        title.append(providerIconString(providerID, color: palette.icon))
        title.append(NSAttributedString(string: " ", attributes: [.font: labelFont]))
        for (index, metric) in metrics.enumerated() {
            if index > 0 { title.append(dividerString(color: palette.text)) }
            title.append(metricSegment(metric, style: style, palette: palette))
        }
        button.attributedTitle = title
    }

    /// Renders the pinned provider's brand mark as a leading, tinted
    /// attachment so the menu bar makes clear at a glance whose numbers these
    /// are, without the user having to open the popover.
    private func providerIconString(_ providerID: ProviderID, color: NSColor) -> NSAttributedString {
        guard let logo = NSImage(named: providerID.iconAssetName) else {
            return NSAttributedString()
        }
        logo.size = NSSize(width: 12, height: 12)
        let attachment = NSTextAttachment()
        let tinted = tintedImage(logo, color: color)
        attachment.image = tinted
        let y = (percentFont.capHeight - tinted.size.height) / 2
        attachment.bounds = CGRect(x: 0, y: y, width: tinted.size.width, height: tinted.size.height)
        return NSAttributedString(attachment: attachment)
    }

    private func metricSegment(
        _ metric: UsageMetric,
        style: DetailedModeStyle,
        palette: MenuBarColorPalette
    ) -> NSAttributedString {
        let usage = metric.usedPercent ?? 0
        let duration = metric.windowDuration ?? 0
        let forecast = WindowForecast.make(
            utilization: usage,
            resetsAt: metric.resetsAt,
            duration: duration
        )
        let percentColor = ColorTheme.nsColor(for: forecast, fallbackUsage: usage)
        let units: MenuBarCountdownFormatter.Units = duration >= 24 * 3600
            ? .daysHours
            : .hoursMinutes
        let trailing = style == .countdown
            ? countdownLabel(until: metric.resetsAt, units: units) ?? metric.shortLabel
            : metric.shortLabel
        let symbol = duration >= 24 * 3600 ? "calendar" : "clock"
        let segment = NSMutableAttributedString()
        segment.append(symbolString(symbol, color: palette.icon))
        segment.append(NSAttributedString(string: "  ", attributes: [.font: labelFont]))
        segment.append(NSAttributedString(string: "\(Int(usage))%", attributes: [
            .foregroundColor: percentColor,
            .font: percentFont
        ]))
        segment.append(NSAttributedString(string: " \(trailing)", attributes: [
            .foregroundColor: palette.text,
            .font: labelFont
        ]))
        return segment
    }

    /// Renders each window as `[icon] used% trailing`, matching the reference
    /// menu-bar design: the percentage takes the usage colour, while the icon
    /// and trailing label take the resolved `palette` colours — the muted
    /// secondary tone by default, or the user's custom icon/text colours when
    /// enabled in Appearance settings. A thin vertical divider separates the
    /// 5-hour (clock) and 7-day (calendar) windows.
    private func updateDetailedMode(button: NSStatusBarButton, data: UsageData?, style: DetailedModeStyle, palette: MenuBarColorPalette) {
        button.image = nil

        guard let data = data else {
            button.attributedTitle = mutedTitle("-- | --", color: palette.text)
            return
        }

        var segments: [NSAttributedString] = []

        if let fiveHour = data.fiveHour {
            segments.append(windowSegment(
                fiveHour,
                symbol: "clock",
                fixedLabel: "5h",
                style: style,
                units: .hoursMinutes,
                duration: Constants.Window.fiveHourDuration,
                palette: palette
            ))
        }

        if let sevenDay = data.sevenDay {
            segments.append(windowSegment(
                sevenDay,
                symbol: "calendar",
                fixedLabel: "7d",
                style: style,
                units: .daysHours,
                duration: Constants.Window.sevenDayDuration,
                palette: palette
            ))
        }

        guard !segments.isEmpty else {
            button.attributedTitle = mutedTitle("No data", color: palette.text)
            return
        }

        let title = NSMutableAttributedString()
        for (index, segment) in segments.enumerated() {
            if index > 0 { title.append(dividerString(color: palette.text)) }
            title.append(segment)
        }
        button.attributedTitle = title
    }

    // MARK: - Detailed Mode Rendering

    private var percentFont: NSFont { .monospacedDigitSystemFont(ofSize: 12, weight: .semibold) }
    private var labelFont: NSFont { .monospacedDigitSystemFont(ofSize: 12, weight: .regular) }

    /// Builds one window's `[icon] used% trailing` run.
    /// The percentage is always the used utilization (coloured by level). The
    /// trailing label is the time-until-reset in `.countdown` style — falling
    /// back to the fixed "5h"/"7d" label when no reset time is known — and the
    /// fixed label in `.fixed` style.
    private func windowSegment(
        _ window: UsageWindow,
        symbol: String,
        fixedLabel: String,
        style: DetailedModeStyle,
        units: MenuBarCountdownFormatter.Units,
        duration: TimeInterval,
        palette: MenuBarColorPalette
    ) -> NSAttributedString {
        let usage = window.utilization
        let forecast = WindowForecast.make(utilization: usage, resetsAt: window.resetsAt, duration: duration)
        let percentColor = ColorTheme.nsColor(for: forecast, fallbackUsage: usage)

        let trailing: String
        switch style {
        case .fixed:
            trailing = fixedLabel
        case .countdown:
            trailing = countdownLabel(until: window.resetsAt, units: units) ?? fixedLabel
        }

        let segment = NSMutableAttributedString()
        segment.append(symbolString(symbol, color: palette.icon))
        segment.append(NSAttributedString(string: "  ", attributes: [.font: labelFont]))
        segment.append(NSAttributedString(string: "\(Int(usage))%", attributes: [
            .foregroundColor: percentColor,
            .font: percentFont
        ]))
        segment.append(NSAttributedString(string: " ", attributes: [.font: labelFont]))
        segment.append(NSAttributedString(string: trailing, attributes: [
            .foregroundColor: palette.text,
            .font: labelFont
        ]))
        return segment
    }

    /// Thin vertical divider drawn between the two windows.
    private func dividerString(color: NSColor) -> NSAttributedString {
        return NSAttributedString(string: "  |  ", attributes: [
            .foregroundColor: color.withAlphaComponent(0.5),
            .font: labelFont
        ])
    }

    /// Neutral placeholder title used for the no-data / loading states.
    private func mutedTitle(_ string: String, color: NSColor) -> NSAttributedString {
        return NSAttributedString(string: string, attributes: [
            .foregroundColor: color,
            .font: labelFont
        ])
    }

    /// Renders an SF Symbol as an inline, vertically-centred, tinted attachment.
    private func symbolString(_ name: String, color: NSColor) -> NSAttributedString {
        let attachment = NSTextAttachment()
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        if let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let tinted = tintedImage(symbol, color: color)
            attachment.image = tinted
            // Centre the glyph on the text's cap height.
            let y = (percentFont.capHeight - tinted.size.height) / 2
            attachment.bounds = CGRect(x: 0, y: y, width: tinted.size.width, height: tinted.size.height)
        }
        return NSAttributedString(attachment: attachment)
    }

    /// Returns a non-template copy of `image` filled with `color`.
    private func tintedImage(_ image: NSImage, color: NSColor) -> NSImage {
        let size = image.size
        let tinted = NSImage(size: size)
        tinted.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        color.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.isTemplate = false
        return tinted
    }

    /// Build a collapsed countdown label from now until `resetsAt`.
    /// Returns nil when the reset time is missing or already past.
    private func countdownLabel(until resetsAt: Date?, units: MenuBarCountdownFormatter.Units) -> String? {
        guard let resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSinceNow
        return MenuBarCountdownFormatter.label(remaining: remaining, units: units)
    }

    // MARK: - Progress Icon Creation

    /// Creates a circular progress icon for the menu bar
    private func createProgressIcon(progress: Double, color: Color) -> NSImage {
        let size = NSSize(width: iconSize, height: iconSize)
        let image = NSImage(size: size, flipped: false) { rect in
            let context = NSGraphicsContext.current?.cgContext
            context?.clear(rect)

            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2 - 2
            let lineWidth: CGFloat = 2.5

            // Background circle (gray)
            let backgroundPath = NSBezierPath()
            backgroundPath.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 0,
                endAngle: 360
            )
            NSColor.systemGray.withAlphaComponent(0.3).setStroke()
            backgroundPath.lineWidth = lineWidth
            backgroundPath.stroke()

            // Progress arc
            let clampedProgress = min(max(progress, 0), 1)
            if clampedProgress > 0 {
                let startAngle: CGFloat = 90  // Start from top
                let endAngle: CGFloat = 90 - (CGFloat(clampedProgress) * 360)

                let progressPath = NSBezierPath()
                progressPath.appendArc(
                    withCenter: center,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: true
                )
                NSColor(color).setStroke()
                progressPath.lineWidth = lineWidth
                progressPath.lineCapStyle = .round
                progressPath.stroke()
            }

            return true
        }

        image.isTemplate = false
        return image
    }

    // MARK: - Popover Toggle

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let statusItem = statusItem,
              let popover = popover,
              let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
            removeEventMonitor()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            setupEventMonitor()

            // Only refresh if data is stale
            if appState.pollingManager.isDataStale(lastUpdateTime: appState.lastUpdateTime) {
                Task {
                    await appState.refresh(reason: "popover_open")
                }
            }
        }
    }

    // MARK: - Public Methods

    func showPopover() {
        guard let statusItem = statusItem,
              let popover = popover,
              let button = statusItem.button,
              !popover.isShown else { return }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func hidePopover() {
        guard let popover = popover, popover.isShown else { return }
        popover.performClose(nil)
        removeEventMonitor()
    }

    // MARK: - Event Monitor

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self,
                  let popover = self.popover,
                  popover.isShown else { return }

            self.hidePopover()
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - NSPopoverDelegate

extension StatusItemController: NSPopoverDelegate {
    func popoverDidShow(_ notification: Notification) {
        appState.isPopoverShown = true
    }

    func popoverDidClose(_ notification: Notification) {
        appState.isPopoverShown = false
        removeEventMonitor()
    }
}

// MARK: - Menu Bar Color Palette

/// Resolves the icon and text colors for the Detailed menu-bar mode.
/// When custom colors are disabled the app falls back to the adaptive
/// `.secondaryLabelColor` — its original appearance.
struct MenuBarColorPalette {
    let icon: NSColor
    let text: NSColor

    static func resolve(from settings: AppSettings) -> MenuBarColorPalette {
        guard settings.customMenuBarColorsEnabled else {
            return MenuBarColorPalette(icon: .secondaryLabelColor, text: .secondaryLabelColor)
        }
        return MenuBarColorPalette(
            icon: NSColor(Color(hex: settings.menuBarIconColorHex)),
            text: NSColor(Color(hex: settings.menuBarTextColorHex))
        )
    }
}
