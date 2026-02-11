//
//  Bus.swift
//  CABSFlight
//
//  Created by Steve on 2/7/26.
//

import Foundation
import CoreLocation

/// Represents a CABS bus vehicle with real-time position data
struct Bus: Identifiable, Codable, Equatable {
    let id: String
    let routeCode: String
    let latitude: Double
    let longitude: Double
    let heading: Double
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
    
    /// For smooth animation interpolation between position updates
    func interpolated(to target: Bus, progress: Double) -> Bus {
        // Interpolate heading with shortest-path rotation
        var headingDiff = target.heading - heading
        if headingDiff > 180 { headingDiff -= 360 }
        if headingDiff < -180 { headingDiff += 360 }
        
        return Bus(
            id: id,
            routeCode: routeCode,
            latitude: latitude + (target.latitude - latitude) * progress,
            longitude: longitude + (target.longitude - longitude) * progress,
            heading: heading + headingDiff * progress,
            speed: target.speed,
            destination: target.destination,
            delayed: target.delayed,
            patternId: target.patternId,
            nextStopID: target.nextStopID,
            distance: target.distance,
            lastUpdated: target.lastUpdated
        )
    }
}
