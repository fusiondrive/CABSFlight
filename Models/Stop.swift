//
//  Stop.swift
//  CABSFlight
//
//  Created by Steve on 2/7/26.
//

import Foundation
import CoreLocation

/// Represents a bus stop along a CABS route
struct Stop: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
