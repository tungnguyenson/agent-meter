//
//  ProgressRingView.swift
//  AgentMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI

struct ProgressRingView: View {
    var progress: Double // 0 to 1
    var color: Color
    var lineWidth: CGFloat = 8
    var size: CGFloat = 80

    @Environment(\.colorScheme) private var colorScheme

    /// A colored track at a fixed opacity reads noticeably fainter on a light
    /// window background than a dark one, so light mode gets a stronger tint
    /// to keep the unfilled portion of the ring visible.
    private var trackOpacity: Double {
        colorScheme == .dark ? 0.12 : 0.2
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(trackOpacity), lineWidth: lineWidth)
            
            Circle()
                .trim(from: 0.0, to: min(progress, 1.0))
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .foregroundColor(color)
                .rotationEffect(Angle(degrees: 270.0))
                .animation(.linear, value: progress)
        }
        .frame(width: size, height: size)
    }
}
