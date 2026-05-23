//
//  BusBadgeView.swift
//  CABSFlightWidgetExtension
//
//  Reusable route-code badge for the Live Activity layouts.
//
//  Color source: CABSColors.color(for:) — the same function the main app uses.
//  No color values are defined here. To add or change a route color, edit
//  CABSColors.swift only (and make sure it stays in both target memberships).
//

import SwiftUI

// MARK: - BusBadgeView

/// A solid rounded-rectangle badge that shows the route code in white text.
/// `size` controls the square frame; corner radius and font scale automatically.
/// Empty or unknown route codes never crash — they show "?" in graphite.
struct BusBadgeView: View {
    let routeCode: String
    var size: CGFloat = 40

    private var color: Color  { CABSColors.color(for: routeCode) }
    private var corner: CGFloat { size * 0.28 }
    private var fontSize: CGFloat {
        switch routeCode.count {
        case ...2:  return size * 0.36
        case 3:     return size * 0.30
        default:    return size * 0.24
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(color)
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.18), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                )

            Text(routeCode.isEmpty ? "?" : routeCode)
                .font(.system(size: fontSize, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 3)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("BusBadgeView — all routes") {
    HStack(spacing: 12) {
        ForEach(["BE", "CC", "CLS", "ER", "MC", "NWC", "WMC", "???"], id: \.self) { code in
            VStack(spacing: 6) {
                BusBadgeView(routeCode: code, size: 48)
                Text(code)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding()
}
#endif
