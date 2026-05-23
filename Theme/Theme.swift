//
//  Theme.swift
//  CABSFlight
//
//  Created by Steve on 2/7/26.
//

import SwiftUI

/// Flighty-inspired dark theme constants
enum Theme {
    // MARK: - Colors
    
    /// Deep black background
    static let background = Color(hex: "#0A0A0A")
    
    /// Slightly elevated card background
    static let cardBackground = Color(hex: "#1A1A1A")
    
    /// Subtle border color
    static let border = Color.white.opacity(0.08)
    
    /// Primary accent - electric blue
    static let accent = Color(hex: "#007AFF")
    
    /// Secondary accent - warm gold
    static let accentSecondary = Color(hex: "#FFD60A")
    
    /// Primary text
    static let textPrimary = Color.white
    
    /// Secondary text
    static let textSecondary = Color.white.opacity(0.6)
    
    /// Tertiary/muted text
    static let textTertiary = Color.white.opacity(0.35)
    
    // MARK: - Typography
    
    static func headerFont(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }
    
    static func titleFont(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }
    
    static func bodyFont(_ size: CGFloat = 16) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }
    
    static func captionFont(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }
    
    // MARK: - Spacing
    
    static let paddingSmall: CGFloat = 8
    static let paddingMedium: CGFloat = 16
    static let paddingLarge: CGFloat = 24
    
    // MARK: - Corner Radius
    
    static let cornerRadiusSmall: CGFloat = 8
    static let cornerRadiusMedium: CGFloat = 12
    static let cornerRadiusLarge: CGFloat = 20
    
    // MARK: - Animation
    
    static let animationSpring = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let animationSmooth = Animation.easeInOut(duration: 0.3)

    /// Snappy press animation for map annotations and icon buttons.
    static let animationMapTap = Animation.spring(response: 0.2, dampingFraction: 0.6)
}

// MARK: - Map Item Button Style

/// Standard press feedback for non-MapKit buttons (toolbar items, cards, etc.).
/// MapKit Annotation closures need `mapItemPressEffect()` instead — see below.
struct CABSMapItemButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .brightness(configuration.isPressed ? -0.15 : 0)
            .animation(Theme.animationMapTap, value: configuration.isPressed)
    }
}

// MARK: - Map Item Press Modifier

/// Use this instead of `CABSMapItemButtonStyle` inside `Annotation` closures.
///
/// Two problems solved here:
///
/// 1. **ButtonStyle.isPressed is swallowed by MapKit.**  MapKit installs a
///    UIGestureRecognizer on every annotation host view at the UIKit layer,
///    consuming the touch before SwiftUI's button machinery sees it.  We bypass
///    this by using `DragGesture(minimumDistance: 0)` with `.simultaneousGesture`
///    — it fires on raw touch-down/up without competing with MapKit's tap
///    recogniser, and calling `action()` from `.onEnded` means the tap is
///    never swallowed.
///
/// 2. **Selection state needs to persist.**  The effect is active whenever
///    `isPressed || isSelected`, so the darkened/scaled-down look stays on the
///    annotation for as long as it is the current selection — not just during
///    the instant of the press.
///
/// Usage:
///
///     LiquidStationView(...)
///         .contentShape(Rectangle())
///         .mapItemPressEffect(isSelected: viewModel.selectedStop?.id == stop.id) {
///             viewModel.selectStop(stop)
///         }
///
struct MapItemPressEffect: ViewModifier {
    /// Whether this annotation is the currently active/selected item.
    let isSelected: Bool
    /// Fired on touch-up (guarded against accidental short drags).
    let action: () -> Void

    @State private var isPressed = false

    func body(content: Content) -> some View {
        let active = isPressed || isSelected
        return content
            .scaleEffect(active ? 0.96 : 1.0)
            .brightness(active ? -0.15 : 0)
            .animation(Theme.animationMapTap, value: active)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !isPressed { isPressed = true } }
                    .onEnded { value in
                        isPressed = false
                        // Treat as a tap only when the finger barely moved;
                        // ignore genuine drags (panning the map).
                        let t = value.translation
                        guard abs(t.width) < 10, abs(t.height) < 10 else { return }
                        action()
                    }
            )
    }
}

extension View {
    /// Attach persistent press + selection feedback to a MapKit Annotation view.
    /// The action closure replaces `.onTapGesture` — do not add both.
    func mapItemPressEffect(isSelected: Bool, action: @escaping () -> Void) -> some View {
        modifier(MapItemPressEffect(isSelected: isSelected, action: action))
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
