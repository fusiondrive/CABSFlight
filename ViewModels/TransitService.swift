//
//  TransitService.swift
//  CABSFlight
//
//  Protocol-oriented data layer for transit data.
//  Swap CABSMockService for a live implementation without touching any view or view model.
//

import Foundation
import CoreLocation

// MARK: - Route Geometry

/// Shared geometry helpers for the simulated data sources. Both mock services
/// derive a vehicle's heading from the *same* route segment used to place it,
/// so the arrow always points along the path the coordinate is travelling.
enum RouteGeometry {
    /// Below this separation (in degrees, ~1 cm) a segment is treated as
    /// zero-length and yields no bearing.
    private static let epsilon = 1e-7

    static func coincident(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
        abs(a.latitude - b.latitude) < epsilon && abs(a.longitude - b.longitude) < epsilon
    }

    /// Great-circle forward bearing from `a` to `b`, normalized to `0..<360`.
    ///
    /// Uses the full spherical formula, which folds in the longitude
    /// compression by `cos(latitude)`. A naive `atan2(Δlon, Δlat)` omits that
    /// factor and, on a projected map at ~40°N, rotates the arrow several
    /// degrees off the route (worse on east–west and diagonal segments).
    ///
    /// Returns `nil` for a zero-length segment so callers never fabricate 0°.
    /// The result is a plain normalized heading — shortest-arc continuity is
    /// the presentation layer's job (`DisplayedBus.unwrappedHeading`), never
    /// the data source's.
    static func forwardBearing(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D
    ) -> Double? {
        guard !coincident(a, b) else { return nil }
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }
}

/// Lightweight arrival prediction returned by the service layer.
/// The richer ArrivalPrediction with spatial ETA logic is computed in BusViewModel.
struct Prediction: Identifiable, Hashable, Sendable {
    let id: String
    let routeCode: String
    let vehicleID: String
    let stopID: String
    let arrivalSeconds: Double

    var timeDisplay: String {
        guard arrivalSeconds >= 60 else { return "Due" }
        return "\(max(1, Int(ceil(arrivalSeconds / 60)))) min"
    }
}

/// The single contract that all data sources — mock or live — must satisfy.
protocol TransitService: Sendable {
    /// Returns all available routes, each pre-populated with stops and patterns.
    func fetchRoutes() async throws -> [Route]

    /// Returns the current vehicle positions for a given route code.
    func fetchVehicles(routeCode: String) async throws -> [Bus]

    /// Returns arrival predictions for a specific stop across all serving routes.
    func fetchPredictions(stopID: String) async throws -> [Prediction]
}
