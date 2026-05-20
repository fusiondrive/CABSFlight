//
//  CABSFlightLiveActivity.swift
//  CABSFlightWidgetExtension
//
//  Renders the Live Activity for an upcoming bus arrival — Lock Screen banner
//  and all three Dynamic Island presentations.
//
//  Crash-safety notes:
//  • Never use Text(timerInterval: a...b) — if b < a the range is invalid and
//    the snapshot renderer throws BSActionErrorDomain Code=6 ("anulled").
//    Use Text(date, style: .timer) instead; it handles past dates gracefully.
//  • Avoid GeometryReader and TimelineView at the top level of snapshots.
//  • Never reference host-app singletons (CABSMockEngine, BusViewModel, etc.).
//    This extension is a separate process; only context.state / context.attributes
//    are accessible.
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
            .activityBackgroundTint(Color.black.opacity(0.55))
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
                    IslandBottom(state: context.state)
                }
            } compactLeading: {
                IslandCompactLeading(routeCode: context.attributes.routeCode)
            } compactTrailing: {
                IslandCompactTrailing(state: context.state)
            } minimal: {
                IslandMinimal(routeCode: context.attributes.routeCode)
            }
            .keylineTint(routeColor(for: context.attributes.routeCode))
        }
    }
}

// =============================================================================
// MARK: - Lock Screen Banner
// =============================================================================

private struct LockScreenBanner: View {
    let attributes: CABSFlightAttributes
    let state: CABSFlightAttributes.ContentState

    private var color: Color { routeColor(for: attributes.routeCode) }

    var body: some View {
        HStack(spacing: 14) {
            // Route badge column
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(color.gradient)
                        .frame(width: 44, height: 44)
                        .shadow(color: color.opacity(0.45), radius: 8, x: 0, y: 4)
                    Image(systemName: "bus.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text(attributes.routeCode.isEmpty ? "BUS" : attributes.routeCode)
                    .font(.caption2.bold())
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(color.opacity(0.35)))
            }

            // Destination + delay chip
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
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.orange.opacity(0.18)))
                }
            }

            Spacer(minLength: 4)

            // Countdown — safe single-date style, never crashes on past dates
            VStack(alignment: .trailing, spacing: 2) {
                Text(state.estimatedArrivalTimestamp, style: .timer)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(state.isDelayed ? Color.orange : .white)
                    .frame(maxWidth: 96, alignment: .trailing)
                Text("ETA")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            ZStack {
                LinearGradient(
                    colors: [color.opacity(0.55), Color.black.opacity(0.65)],
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

// MARK: Compact

private struct IslandCompactLeading: View {
    let routeCode: String
    var body: some View {
        ZStack {
            Circle().fill(routeColor(for: routeCode).gradient)
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
        Text(state.estimatedArrivalTimestamp, style: .timer)
            .monospacedDigit()
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(state.isDelayed ? Color.orange : .white)
            .frame(width: 44)
            .multilineTextAlignment(.trailing)
    }
}

// MARK: Minimal

private struct IslandMinimal: View {
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

// MARK: Expanded

private struct IslandLeading: View {
    let routeCode: String
    let stopName: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(routeColor(for: routeCode).gradient)
                    .frame(width: 38, height: 38)
                Text(routeCode.isEmpty ? "?" : routeCode)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
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
            Text(state.estimatedArrivalTimestamp, style: .timer)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(state.isDelayed ? Color.orange : .white)
                .frame(maxWidth: 88, alignment: .trailing)
            Text(state.isDelayed ? "Delayed" : "On time")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(state.isDelayed ? .orange : .green)
        }
        .padding(.trailing, 4)
    }
}

private struct IslandBottom: View {
    let state: CABSFlightAttributes.ContentState

    // Progress track: 0 = 10+ min away, 1 = arriving now.
    private static let windowSeconds: TimeInterval = 10 * 60

    var body: some View {
        // Use Text's built-in timer for a live "X min" label.
        // Avoid TimelineView at the top level — the system snapshot renderer
        // may not initialise it correctly and will annul the snapshot.
        HStack(spacing: 8) {
            Image(systemName: "bus.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(state.isDelayed ? Color.orange : .white)
            Text(state.estimatedArrivalTimestamp, style: .relative)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(state.isDelayed ? Color.orange : .white.opacity(0.85))
                .lineLimit(1)
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
// MARK: - Route color mapping (no host-app dependency)
// =============================================================================

private func routeColor(for code: String) -> Color {
    switch code.uppercased() {
    case "CLNS": return Color(red: 200/255, green: 16/255,  blue: 46/255)
    case "EWE":  return Color(red: 30/255,  green: 102/255, blue: 245/255)
    case "BL":   return Color(red: 19/255,  green: 123/255, blue: 63/255)
    case "CC":   return Color(red: 245/255, green: 158/255, blue: 11/255)
    case "WMC":  return Color(red: 128/255, green: 0/255,   blue: 128/255)
    default:     return Color(red: 120/255, green: 120/255, blue: 130/255)
    }
}

// =============================================================================
// MARK: - Previews
// =============================================================================

#if DEBUG
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
