//
//  CABSColors.swift
//  CABSFlight
//
//  Official CABS route colors (Adobe RGB values)
//

import SwiftUI

/// Official CABS route colors from OSU Transportation
enum CABSColors {
    /// Get the official color for a route by its ID
    static func color(for routeID: String) -> Color {
        switch routeID.uppercased() {
        case "BE":
            return Color(red: 0.814, green: 0.452, blue: 0.120)
        case "CC":
            return Color(red: 0.300, green: 0.524, blue: 0.185)
        case "CLS":
            return Color(red: 0.735, green: 0.215, blue: 0.169)
        case "ER":
            return Color(red: 0.328, green: 0.482, blue: 0.608)
        case "MC":
            return Color(red: 0.868, green: 0.346, blue: 0.544)
        case "NWC":
            return Color(red: 0.661, green: 0.481, blue: 0.853)
        case "WMC":
            return Color(red: 0.532, green: 0.758, blue: 0.784)
        default:
            // Fallback to a neutral gray for unknown routes
            return Color(red: 0.5, green: 0.5, blue: 0.5)
        }
    }
}

extension Route {
    /// Official CABS color for this route (overrides API color)
    var officialColor: Color {
        CABSColors.color(for: id)
    }
}
