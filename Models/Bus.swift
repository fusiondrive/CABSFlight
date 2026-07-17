//
//  Bus.swift
//  CABSFlight
//
//  Created by Steve on 2/7/26.
//

import Foundation
import CoreLocation

/// Represents a CABS bus vehicle with real-time position data
struct Bus: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: String
    let routeCode: String
    let latitude: Double
    let longitude: Double
    /// Compass heading in degrees (0° = true north, valid range 0..<360).
    /// `nil` means the data source reported no valid heading — 0° itself is a
    /// legitimate northbound value and must never be treated as "missing".
    let heading: Double?
    let speed: Int
    let destination: String?
    let delayed: Bool
    let patternId: String?
    let nextStopID: String?
    let distance: Int?
    let lastUpdated: Date?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
