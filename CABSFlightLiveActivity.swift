//
//  CABSFlightLiveActivity.swift
//  CABSFlightWidgetExtension
//
//  Widget Extension entry point that renders the Live Activity for an
//  upcoming bus arrival — both as the Lock Screen banner and across all
//  three Dynamic Island presentations.
//
//  Architectural notes:
//  • This file lives in the *widget extension target*. It must NOT import
//    CABSMockEngine; the engine drives the host app which then pushes
//    ContentState updates via `Activity.update(...)`. Keeping the widget
//    pure means previews here are deterministic and the widget compiles
//    even when the mock engine evolves.
//  • All countdowns use `Text(timerInterval:countsDown:)` so the system
//    re-renders them every second without ActivityKit pushes (battery).
//  • Visual language: Material Design 3 + Bento card composition with
//    glassmorphism via `.background(.ultraThinMaterial)`.
//
//  Add this file to the Widget Extension target only.
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Widget bundle entry

@main
struct CABSFlightWidgetBundle: WidgetBundle {
    var body: some Widget {
        CABSFlightLiveActivity()
    }
}

// MARK: - The Live Activity

struct CABSFlightLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CABSFlightAttributes.self) { context in
            // MARK: Lock Screen / Banner View
            LockScreenView(
                attributes: context.attributes,
                state: context.state
            )
            .activityBackgroundTint(Color.black.opacity(0.55))
            .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: Expanded — Bento dashboard
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeading(
                        routeCode: context.attributes.routeCode,
                        stopName: context.attributes.stopName
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottom(state: context.state)
                }

            } compactLeading: {
                // MARK: Compact Leading — colored route badge
                CompactLeading(routeCode: context.attributes.routeCode)

            } compactTrailing: {
                // MARK: Compact Trailing — concise relative timer
                CompactTrailing(state: context.state)

            } minimal: {
                // MARK: Minimal — single glyph
                MinimalView(routeCode: context.attributes.routeCode)
            }
            .keylineTint(routeColor(for: context.attributes.routeCode))
        }
    }
}

// =============================================================================
// MARK: - Lock Screen View (Glassmorphism Bento capsule)
// =============================================================================

private struct LockScreenView: View {
    let attributes: CABSFlightAttributes
    let state: CABSFlightAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {

            // Left — colored route pill + bus glyph
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(routeColor(for: attributes.routeCode).gradient)
                        .frame(width: 42, height: 42)
                        .shadow(color: routeColor(for: attributes.routeCode).opacity(0.45),
                                radius: 8, x: 0, y: 4)
                    Image(systemName: "bus.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text(attributes.routeCode)
                    .font(.caption2).bold()
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(
                        Capsule().fill(routeColor(for: attributes.routeCode).opacity(0.35))
                    )
            }

            // Middle — destination + delay chip
            VStack(alignment: .leading, spacing: 4) {
                Text("Arriving at")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
                Text(attributes.stopName)
                    .font(.headline).bold()
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if state.isDelayed {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Delayed")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.orange.opacity(0.18)))
                }
            }

            Spacer(minLength: 4)

            // Right — large native countdown
            VStack(alignment: .trailing, spacing: 2) {
                Text(timerInterval: Date()...state.estimatedArrivalTimestamp,
                     countsDown: true)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(state.isDelayed ? Color.orange : .white)
                    .frame(maxWidth: 96)
                Text("ETA")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            // Glassmorphism: tinted gradient under ultra-thin material.
            ZStack {
                LinearGradient(
                    colors: [
                        routeColor(for: attributes.routeCode).opacity(0.55),
                        Color.black.opacity(0.65)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Rectangle().fill(.ultraThinMaterial)
            }
        }
    }
}

// =============================================================================
// MARK: - Dynamic Island regions
// =============================================================================

// ----- Compact -----

private struct CompactLeading: View {
    let routeCode: String
    var body: some View {
        ZStack {
            Circle()
                .fill(routeColor(for: routeCode).gradient)
            Image(systemName: "bus.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 22, height: 22)
    }
}

private struct CompactTrailing: View {
    let state: CABSFlightAttributes.ContentState
    var body: some View {
        Text(timerInterval: Date()...state.estimatedArrivalTimestamp,
             countsDown: true,
             showsHours: false)
            .monospacedDigit()
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(state.isDelayed ? Color.orange : .white)
            .frame(width: 44)
            .multilineTextAlignment(.trailing)
    }
}

private struct MinimalView: View {
    let routeCode: String
    var body: some View {
        ZStack {
            Circle().fill(routeColor(for: routeCode).gradient)
            Image(systemName: "bus.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

// ----- Expanded (Bento dashboard) -----

private struct ExpandedLeading: View {
    let routeCode: String
    let stopName: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(routeColor(for: routeCode).gradient)
                    .frame(width: 38, height: 38)
                Text(routeCode)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Destination")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(stopName)
                    .font(.subheadline).bold()
                    .lineLimit(1)
                    .foregroundStyle(.white)
            }
        }
        .padding(.leading, 4)
    }
}

private struct ExpandedTrailing: View {
    let state: CABSFlightAttributes.ContentState
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(timerInterval: Date()...state.estimatedArrivalTimestamp,
                 countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(state.isDelayed ? Color.orange : .white)
                .frame(maxWidth: 88)
            Text(state.isDelayed ? "Delayed" : "On time")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(state.isDelayed ? .orange : .green)
        }
        .padding(.trailing, 4)
    }
}

private struct ExpandedBottom: View {
    let state: CABSFlightAttributes.ContentState

    /// Window for the dotted progress track. A bus that's 10+ minutes out
    /// starts with the first dot lit; the closer the ETA, the more dots fill.
    private static let progressWindowSeconds: TimeInterval = 10 * 60

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { ctx in
            let remaining = max(0, state.estimatedArrivalTimestamp.timeIntervalSince(ctx.date))
            let progress = 1.0 - min(1.0, remaining / Self.progressWindowSeconds)
            ProximityDotsTrack(progress: progress,
                               tint: state.isDelayed ? .orange : .white)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        }
    }
}

// =============================================================================
// MARK: - Reusable: linear dotted proximity track
// =============================================================================

private struct ProximityDotsTrack: View {
    /// 0.0 = bus is far / window start, 1.0 = arriving now.
    let progress: Double
    let tint: Color
    var dotCount: Int = 12

    var body: some View {
        GeometryReader { geo in
            let spacing = geo.size.width / CGFloat(dotCount - 1)
            ZStack(alignment: .leading) {
                // Dim rail
                HStack(spacing: 0) {
                    ForEach(0..<dotCount, id: \.self) { i in
                        Circle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 6, height: 6)
                        if i < dotCount - 1 { Spacer(minLength: 0) }
                    }
                }
                // Lit dots based on progress
                HStack(spacing: 0) {
                    ForEach(0..<dotCount, id: \.self) { i in
                        let threshold = Double(i) / Double(dotCount - 1)
                        Circle()
                            .fill(threshold <= progress ? tint : Color.clear)
                            .frame(width: 8, height: 8)
                            .shadow(color: tint.opacity(threshold <= progress ? 0.6 : 0),
                                    radius: 4)
                        if i < dotCount - 1 { Spacer(minLength: 0) }
                    }
                }
                // Bus glyph follows the head of the progress
                Image(systemName: "bus.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                    .offset(x: spacing * CGFloat(dotCount - 1) * CGFloat(progress) - 6,
                            y: -14)
                    .animation(.easeOut(duration: 0.6), value: progress)
            }
        }
        .frame(height: 22)
    }
}

// =============================================================================
// MARK: - Route → Color mapping
// =============================================================================
//
// Mirrors the colors used in CABSMockEngine, but kept here intentionally so
// the widget target has no dependency on the mock engine module.
//

fileprivate func routeColor(for code: String) -> Color {
    switch code.uppercased() {
    case "CLNS":       return Color(red: 200/255, green: 16/255,  blue: 46/255)   // scarlet
    case "EWE":        return Color(red: 30/255,  green: 102/255, blue: 245/255)  // blue
    case "BL":         return Color(red: 19/255,  green: 123/255, blue: 63/255)   // green
    case "CC":         return Color(red: 245/255, green: 158/255, blue: 11/255)   // amber
    default:           return Color(red: 120/255, green: 120/255, blue: 130/255)  // graphite
    }
}

// =============================================================================
// MARK: - Previews
// =============================================================================

#if DEBUG
import ActivityKit

#Preview("Lock Screen — On Time", as: .content, using: CABSFlightAttributes.preview) {
    CABSFlightLiveActivity()
} contentStates: {
    CABSFlightAttributes.ContentState.arrivingSoon
}

#Preview("Lock Screen — Delayed", as: .content, using: CABSFlightAttributes.preview) {
    CABSFlightLiveActivity()
} contentStates: {
    CABSFlightAttributes.ContentState.delayed
}

#Preview("Dynamic Island — Expanded", as: .dynamicIsland(.expanded), using: CABSFlightAttributes.preview) {
    CABSFlightLiveActivity()
} contentStates: {
    CABSFlightAttributes.ContentState.arrivingSoon
}

#Preview("Dynamic Island — Compact", as: .dynamicIsland(.compact), using: CABSFlightAttributes.preview) {
    CABSFlightLiveActivity()
} contentStates: {
    CABSFlightAttributes.ContentState.arrivingSoon
}

#Preview("Dynamic Island — Minimal", as: .dynamicIsland(.minimal), using: CABSFlightAttributes.preview) {
    CABSFlightLiveActivity()
} contentStates: {
    CABSFlightAttributes.ContentState.delayed
}
#endif
