//
//  CABSFlightLiveActivity.swift
//  CABSFlightWidgetExtension
//
//  Renders the Live Activity for an upcoming bus arrival — Lock Screen banner
//  and all three Dynamic Island presentations.
//
//  Design notes:
//  • Colors come from CABSColors.color(for:) — the same function the main app
//    uses. No color values are defined here or in BusBadgeView.swift.
//    To change a route color, edit CABSColors.swift only.
//  • ETAs are minute-granularity, not ticking seconds — the CABS API is not
//    precise to the second, so ticking creates false urgency.
//  • The entire Lock Screen card tints to the route's brand color via
//    activityBackgroundTint, so each route feels visually distinct.
//  • An absolute clock time (e.g. "8:50 PM") is always shown alongside the
//    minute count — the transit-app standard for conveying schedule certainty.
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Widget bundle

@main
struct CABSFlightWidgetBundle: WidgetBundle {
    var body: some Widget {
        CABSFlightLiveActivity()
    }
}

// MARK: - Live Activity widget

struct CABSFlightLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CABSFlightAttributes.self) { context in

            LockScreenBanner(
                attributes: context.attributes,
                state: context.state
            )
            // The system tints the card container to the route's brand color.
            // Our dark overlay inside ensures text stays readable on any hue.
            .activityBackgroundTint(CABSColors.color(for: context.attributes.routeCode))
            .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandLeading(
                        routeCode: context.attributes.routeCode,
                        stopName:  context.attributes.stopName
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandTrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandBottom(
                        routeCode: context.attributes.routeCode,
                        state: context.state
                    )
                }
            } compactLeading: {
                IslandCompactLeading(routeCode: context.attributes.routeCode)
            } compactTrailing: {
                IslandCompactTrailing(state: context.state)
            } minimal: {
                IslandMinimal(routeCode: context.attributes.routeCode)
            }
            .keylineTint(CABSColors.color(for: context.attributes.routeCode))
        }
    }
}

// =============================================================================
// MARK: - ETA formatting helpers
// =============================================================================

/// Remaining whole minutes until `date`. Floors at 0.
private func minutesUntil(_ date: Date) -> Int {
    max(0, Int(date.timeIntervalSinceNow / 60))
}

/// Short form for compact slots: "4m" / "Due"
private func compactETA(to date: Date) -> String {
    let m = minutesUntil(date)
    return m > 0 ? "\(m)m" : "Due"
}

/// Long form for banner / expanded: "4 min" / "Arriving"
private func fullETA(to date: Date) -> String {
    let m = minutesUntil(date)
    return m > 0 ? "\(m) min" : "Arriving"
}

// =============================================================================
// MARK: - Lock Screen Banner
// =============================================================================

private struct LockScreenBanner: View {
    let attributes: CABSFlightAttributes
    let state: CABSFlightAttributes.ContentState

    private var color: Color { CABSColors.color(for: attributes.routeCode) }

    var body: some View {
        HStack(spacing: 14) {

            // ── Left column: BusBadgeView (dynamic route code + brand color) ──
            BusBadgeView(routeCode: attributes.routeCode, size: 52)
                .shadow(color: color.opacity(0.5), radius: 8, x: 0, y: 4)

            // ── Centre: destination + optional delay chip ─────────────────────
            VStack(alignment: .leading, spacing: 4) {
                Text("Arriving at")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
                Text(attributes.stopName.isEmpty ? "Stop" : attributes.stopName)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if state.isDelayed {
                    Label("Delayed", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.white.opacity(0.22)))
                }
            }

            Spacer(minLength: 4)

            // ── Right: minute ETA + absolute clock time ───────────────────────
            VStack(alignment: .trailing, spacing: 2) {
                Text(fullETA(to: state.estimatedArrivalTimestamp))
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(state.estimatedArrivalTimestamp, style: .time)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        // Dark scrim ensures readability regardless of the activityBackgroundTint hue
        .background(Color.black.opacity(0.28))
    }
}

// =============================================================================
// MARK: - Dynamic Island regions
// =============================================================================

// MARK: Compact

private struct IslandCompactLeading: View {
    let routeCode: String
    var body: some View {
        // Compact slot is 22 × 22 pt — circular badge with bus glyph fits better
        // than a square text badge at this size.
        ZStack {
            Circle().fill(CABSColors.color(for: routeCode))
            Image(systemName: "bus.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 22, height: 22)
    }
}

private struct IslandCompactTrailing: View {
    let state: CABSFlightAttributes.ContentState
    var body: some View {
        Text(compactETA(to: state.estimatedArrivalTimestamp))
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(state.isDelayed ? Color.orange : .white)
            .frame(minWidth: 28, alignment: .trailing)
    }
}

// MARK: Minimal

private struct IslandMinimal: View {
    let routeCode: String
    var body: some View {
        ZStack {
            Circle().fill(CABSColors.color(for: routeCode))
            Image(systemName: "bus.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: Expanded

private struct IslandLeading: View {
    let routeCode: String
    let stopName: String

    var body: some View {
        HStack(spacing: 10) {
            // BusBadgeView replaces the old generic bus-icon rectangle
            BusBadgeView(routeCode: routeCode, size: 38)

            VStack(alignment: .leading, spacing: 1) {
                Text("Destination")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(stopName.isEmpty ? "Stop" : stopName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .foregroundStyle(.white)
            }
        }
        .padding(.leading, 4)
    }
}

private struct IslandTrailing: View {
    let state: CABSFlightAttributes.ContentState

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(fullETA(to: state.estimatedArrivalTimestamp))
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(state.isDelayed ? Color.orange : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: 88, alignment: .trailing)
            Text(state.isDelayed ? "Delayed" : "On time")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(state.isDelayed ? .orange : .green)
        }
        .padding(.trailing, 4)
    }
}

private struct IslandBottom: View {
    let routeCode: String
    let state: CABSFlightAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bus.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CABSColors.color(for: routeCode))

            Text("Arrives at ")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            + Text(state.estimatedArrivalTimestamp, style: .time)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(state.isDelayed ? Color.orange : .white)

            Spacer(minLength: 0)

            if state.isDelayed {
                Label("Delayed", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// =============================================================================
// MARK: - Previews
// =============================================================================

#if DEBUG
#Preview("Lock Screen — CLNS (green)", as: .content, using: CABSFlightAttributes.preview) {
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
