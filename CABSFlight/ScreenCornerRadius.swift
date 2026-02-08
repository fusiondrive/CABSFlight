//
//  ScreenCornerRadius.swift
//  CABSFlight
//
//  Device-specific screen corner radius for perfect bezel integration
//

import SwiftUI

/// Provides the optimal corner radius based on the current device
enum ScreenCornerRadius {
    
    /// The corner radius that best matches the current device's physical screen corners
    static var current: CGFloat {
        #if os(iOS)
        let idiom = UIDevice.current.userInterfaceIdiom
        let screenHeight = UIScreen.main.bounds.height
        let screenWidth = UIScreen.main.bounds.width
        let maxDimension = max(screenHeight, screenWidth)
        
        switch idiom {
        case .pad:
            // iPad has subtle corners
            return 24.0
            
        case .phone:
            // Detect device size category based on screen height
            if maxDimension >= 932 {
                // Pro Max / Plus (6.7" displays: 14 Pro Max, 15 Pro Max, 16 Pro Max)
                return 48.0
            } else if maxDimension >= 896 {
                // Pro / Large standard (6.1" to 6.5" displays: X, XS Max, 11-16 Pro)
                return 39.0
            } else if maxDimension >= 812 {
                // Standard notch phones (5.8" to 6.1": X, XS, 11, 12, 13, 14)
                return 39.0
            } else {
                // SE, older rectangular devices
                return 20.0
            }
            
        default:
            return 20.0
        }
        #else
        return 20.0
        #endif
    }
    
    /// Corner radius for cards that sit at the bottom of the screen
    /// Slightly smaller than screen corners for visual offset
    static var bottomCard: CGFloat {
        max(current - 6, 16)
    }
    
    /// Continuous corner style for modern iOS look
    static var cornerStyle: RoundedCornerStyle {
        .continuous
    }
}

// MARK: - View Extension

extension View {
    /// Clips the view to match the device's screen corner radius
    func screenCornerRadius() -> some View {
        clipShape(RoundedRectangle(cornerRadius: ScreenCornerRadius.current, style: .continuous))
    }
    
    /// Clips to bottom card corner radius (slightly smaller than screen)
    func bottomCardCornerRadius() -> some View {
        clipShape(RoundedRectangle(cornerRadius: ScreenCornerRadius.bottomCard, style: .continuous))
    }
}
