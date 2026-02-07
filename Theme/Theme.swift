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
