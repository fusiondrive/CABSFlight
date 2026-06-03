//
//  CABSMockService.swift
//  CABSFlight
//
//  A 100% offline TransitService implementation for mock-driven development.
//
//  ──────────────────────────────────────────────────────────────────────────
//  ARCHITECTURAL CONTRACT
//  ──────────────────────────────────────────────────────────────────────────
//  • Zero networking. No URLSession, Combine publishers, or remote SDKs.
//  • Three distinct simulated routes with realistic OSU campus coordinates.
//  • An internal Task-based ticker advances bus positions every 3 seconds so
//    vehicles move smoothly on the MapKit layer without any external polling.
//  • Conforms to TransitService — swap in a live implementation at any time
//    by changing the default argument in BusViewModel.init(service:).
//  ──────────────────────────────────────────────────────────────────────────

import Foundation
import CoreLocation

@MainActor
final class CABSMockService: TransitService {

    // MARK: - Route & Stop Definitions

    private struct RouteDefinition: Sendable {
        let route: Route
        let waypoints: [CLLocationCoordinate2D]
    }

    // swiftlint:disable line_length
    private static let routeDefinitions: [RouteDefinition] = [

        // ── Campus Connector ──────────────────────────────────────────────
        RouteDefinition(
            route: Route(
                id: "CC",
                name: "CAMPUS CONNECTOR",
                colorHex: "#C8102E",
                stops: [
                    Stop(id: "CC-1", name: "Ohio Union",    latitude: 40.0009, longitude: -83.0285),
                    Stop(id: "CC-2", name: "Mirror Lake",   latitude: 40.0021, longitude: -83.0302),
                    Stop(id: "CC-3", name: "Main Library",  latitude: 40.0050, longitude: -83.0316),
                    Stop(id: "CC-4", name: "Knowlton Hall", latitude: 40.0062, longitude: -83.0279),
                    Stop(id: "CC-5", name: "Dreese Lab",    latitude: 40.0054, longitude: -83.0262),
                    Stop(id: "CC-6", name: "Hopkins Hall",  latitude: 40.0042, longitude: -83.0271),
                ],
                patterns: [RoutePattern(id: "CC-P1", direction: "Loop", encodedPolyline: "", length: 6)]
            ),
            waypoints: [
                CLLocationCoordinate2D(latitude: 40.0009, longitude: -83.0285),
                CLLocationCoordinate2D(latitude: 40.0021, longitude: -83.0302),
                CLLocationCoordinate2D(latitude: 40.0050, longitude: -83.0316),
                CLLocationCoordinate2D(latitude: 40.0062, longitude: -83.0279),
                CLLocationCoordinate2D(latitude: 40.0054, longitude: -83.0262),
                CLLocationCoordinate2D(latitude: 40.0042, longitude: -83.0271),
            ]
        ),

        // ── East Residential ─────────────────────────────────────────────
        RouteDefinition(
            route: Route(
                id: "ER",
                name: "EAST RESIDENTIAL",
                colorHex: "#1E66F5",
                stops: [
                    Stop(id: "ER-1", name: "Scott Hall",      latitude: 40.0062, longitude: -83.0254),
                    Stop(id: "ER-2", name: "Siebert Hall",    latitude: 40.0080, longitude: -83.0195),
                    Stop(id: "ER-3", name: "Boyd Hall",       latitude: 40.0065, longitude: -83.0185),
                    Stop(id: "ER-4", name: "Morrill Tower",   latitude: 40.0001, longitude: -83.0232),
                    Stop(id: "ER-5", name: "Starling-Loving", latitude: 40.0034, longitude: -83.0213),
                ],
                patterns: [RoutePattern(id: "ER-P1", direction: "Loop", encodedPolyline: "", length: 5)]
            ),
            waypoints: [
                CLLocationCoordinate2D(latitude: 40.0062, longitude: -83.0254),
                CLLocationCoordinate2D(latitude: 40.0080, longitude: -83.0195),
                CLLocationCoordinate2D(latitude: 40.0065, longitude: -83.0185),
                CLLocationCoordinate2D(latitude: 40.0001, longitude: -83.0232),
                CLLocationCoordinate2D(latitude: 40.0034, longitude: -83.0213),
            ]
        ),

        // ── Med Center Express ────────────────────────────────────────────
        RouteDefinition(
            route: Route(
                id: "MC",
                name: "MED CENTER EXPRESS",
                colorHex: "#137B3F",
                stops: [
                    Stop(id: "MC-1", name: "University Hospital",   latitude: 40.0015, longitude: -83.0200),
                    Stop(id: "MC-2", name: "James Cancer Hospital", latitude: 40.0003, longitude: -83.0195),
                    Stop(id: "MC-3", name: "Dodd Hall",             latitude: 39.9992, longitude: -83.0222),
                    Stop(id: "MC-4", name: "Meiling Hall",          latitude: 40.0024, longitude: -83.0197),
                    Stop(id: "MC-5", name: "Ross Heart Hospital",   latitude: 40.0010, longitude: -83.0185),
                ],
                patterns: [RoutePattern(id: "MC-P1", direction: "Loop", encodedPolyline: "", length: 5)]
            ),
            waypoints: [
                CLLocationCoordinate2D(latitude: 40.0015, longitude: -83.0200),
                CLLocationCoordinate2D(latitude: 40.0003, longitude: -83.0195),
                CLLocationCoordinate2D(latitude: 39.9992, longitude: -83.0222),
                CLLocationCoordinate2D(latitude: 40.0024, longitude: -83.0197),
                CLLocationCoordinate2D(latitude: 40.0010, longitude: -83.0185),
            ]
        ),
    ]
    // swiftlint:enable line_length

    // MARK: - Internal Bus State

    private struct BusState {
        var routeCode: String
        /// Fractional index into the waypoints array. Advances each tick.
        var progress: Double
        var waypointCount: Int
        var delayed: Bool
        var destination: String
        var patternID: String

        var waypointIndex: Int { Int(progress) % waypointCount }
        var nextWaypointIndex: Int { (waypointIndex + 1) % waypointCount }
        var fraction: Double { progress - Double(Int(progress)) }

        mutating func advance(by step: Double) {
            progress = (progress + step).truncatingRemainder(dividingBy: Double(waypointCount))
        }
    }

    private var busStates: [String: BusState] = [:]
    private var movementTask: Task<Void, Never>?

    // MARK: - Init / Deinit

    init() {
        // Two buses on Campus Connector, offset by half the loop for realistic spacing
        busStates["CC-BUS-1"] = BusState(routeCode: "CC", progress: 0.0, waypointCount: 6, delayed: false, destination: "Ohio Union",    patternID: "CC-P1")
        busStates["CC-BUS-2"] = BusState(routeCode: "CC", progress: 3.0, waypointCount: 6, delayed: false, destination: "Knowlton Hall", patternID: "CC-P1")
        busStates["ER-BUS-1"] = BusState(routeCode: "ER", progress: 1.5, waypointCount: 5, delayed: false, destination: "Siebert Hall",  patternID: "ER-P1")
        busStates["MC-BUS-1"] = BusState(routeCode: "MC", progress: 0.5, waypointCount: 5, delayed: false, destination: "James Cancer Hospital", patternID: "MC-P1")

        startMovementLoop()
    }

    deinit {
        movementTask?.cancel()
    }

    // MARK: - Movement Simulation

    private func startMovementLoop() {
        movementTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                self?.tick()
            }
        }
    }

    /// Advances every bus by ~0.18 waypoints per tick (≈ 17 seconds per stop segment).
    private func tick() {
        let stepPerTick = 0.18
        for key in busStates.keys {
            busStates[key]?.advance(by: stepPerTick)
        }
    }

    // MARK: - Spatial Helpers

    private func coordinate(for state: BusState, waypoints: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        let from = waypoints[state.waypointIndex]
        let to   = waypoints[state.nextWaypointIndex]
        let f    = state.fraction
        return CLLocationCoordinate2D(
            latitude:  from.latitude  + (to.latitude  - from.latitude)  * f,
            longitude: from.longitude + (to.longitude - from.longitude) * f
        )
    }

    private func heading(for state: BusState, waypoints: [CLLocationCoordinate2D]) -> Double {
        let from = waypoints[state.waypointIndex]
        let to   = waypoints[state.nextWaypointIndex]
        let dLat = to.latitude  - from.latitude
        let dLon = to.longitude - from.longitude
        let deg  = atan2(dLon, dLat) * 180.0 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    // MARK: - TransitService

    func fetchRoutes() async throws -> [Route] {
        Self.routeDefinitions.map(\.route)
    }

    func fetchVehicles(routeCode: String) async throws -> [Bus] {
        guard let definition = Self.routeDefinitions.first(where: { $0.route.id == routeCode }) else {
            return []
        }
        let waypoints = definition.waypoints
        let stops     = definition.route.stops

        return busStates
            .filter { $0.value.routeCode == routeCode }
            .map { (id, state) -> Bus in
                let coord    = coordinate(for: state, waypoints: waypoints)
                let hdg      = heading(for: state, waypoints: waypoints)
                let nextStop = stops[state.nextWaypointIndex]
                return Bus(
                    id: id,
                    routeCode: routeCode,
                    latitude: coord.latitude,
                    longitude: coord.longitude,
                    heading: hdg,
                    speed: 18,
                    destination: state.destination,
                    delayed: state.delayed,
                    patternId: state.patternID,
                    nextStopID: nextStop.id,
                    distance: nil,
                    lastUpdated: Date()
                )
            }
    }

    func fetchPredictions(stopID: String) async throws -> [Prediction] {
        var predictions: [Prediction] = []

        for definition in Self.routeDefinitions {
            guard let stopIndex = definition.route.stops.firstIndex(where: { $0.id == stopID }) else {
                continue
            }
            let stopCount      = definition.route.stops.count
            let secondsPerStop = 17.0

            for (busID, state) in busStates where state.routeCode == definition.route.id {
                var stopsAway = (stopIndex - state.waypointIndex + stopCount) % stopCount
                // Bus just passed this stop and will lap around
                if stopsAway == 0 && state.fraction > 0.5 { stopsAway = stopCount }
                let secondsToNextNode = (1.0 - state.fraction) * secondsPerStop
                let arrivalSeconds    = secondsToNextNode + Double(max(0, stopsAway - 1)) * secondsPerStop

                predictions.append(Prediction(
                    id: "\(busID)-\(stopID)",
                    routeCode: definition.route.id,
                    vehicleID: busID,
                    stopID: stopID,
                    arrivalSeconds: arrivalSeconds
                ))
            }
        }

        return predictions.sorted { $0.arrivalSeconds < $1.arrivalSeconds }
    }
}
