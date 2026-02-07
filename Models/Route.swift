//
//  Route.swift
//  CABSFlight
//
//  Created by Steve on 2/7/26.
//

import Foundation
import SwiftUI

/// Represents a CABS bus route (e.g., Campus Loop North)
struct Route: Identifiable, Codable, Equatable {
    let id: String          // Route code: "CLN", "CLS", "ER", etc.
    let name: String        // Display name: "CAMPUS LOOP NORTH"
    let colorHex: String    // Hex color from API (e.g., "#999999")
    var stops: [Stop]
    var patterns: [RoutePattern]
    
    var color: Color {
        Color(hex: colorHex)
    }
    
    /// Create a Route from API response data
    static func from(info: CABSRoutesListResponse.RouteInfo) -> Route {
        Route(
            id: info.code,
            name: info.name,
            colorHex: info.color,
            stops: [],
            patterns: []
        )
    }
}

/// Represents a route pattern with encoded polyline for the route path
struct RoutePattern: Identifiable, Codable, Equatable {
    let id: String
    let direction: String
    let encodedPolyline: String
    let length: Int
}
