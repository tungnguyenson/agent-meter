//
//  AllProvidersView.swift
//  AgentMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI

/// The popover's home screen: every enabled provider at a glance, each showing
/// its pinned metrics. Tapping a provider drills into that provider's full
/// metric list.
struct AllProvidersView: View {
    @ObservedObject var appState: AppState
    let contentPadding: CGFloat
    let onOpenDetail: (ProviderID) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(appState.enabledProviderIDs) { providerID in
                    ProviderSummaryCard(
                        providerID: providerID,
                        state: appState.providerState(providerID),
                        metrics: appState.pinnedMetrics(for: providerID),
                        isMenuBarProvider: providerID == appState.menuBarProviderID,
                        onSetMenuBarProvider: {
                            appState.selectProvider(providerID)
                        },
                        onOpenDetail: { onOpenDetail(providerID) }
                    )
                }

                disabledProvidersHint
            }
            .padding(.horizontal, contentPadding)
            .padding(.vertical, 8)
            .background(ScrollBarHider())
        }
        .scrollIndicators(.hidden)
    }

    /// Providers exist that the user has not switched on. Say so once, quietly —
    /// otherwise an empty-looking overview reads as a bug rather than a setting.
    @ViewBuilder
    private var disabledProvidersHint: some View {
        let disabled = ProviderID.allCases.filter {
            !appState.enabledProviderIDs.contains($0)
        }
        if !disabled.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle")
                    .font(.caption2)
                Text(
                    "\(disabled.map(\.displayName).formatted(.list(type: .and))) "
                    + "\(disabled.count == 1 ? "is" : "are") off — enable in Settings."
                )
                .font(.caption2)
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.top, 2)
        }
    }
}
