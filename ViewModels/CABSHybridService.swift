//
//  CABSHybridService.swift
//  CABSFlight
//
//  Hybrid TransitService implementation:
//    • REAL static geometry  — routes, stops, and encoded polylines fetched
//      live from the official OSU CABS API on first load.
//    • SIMULATED dynamic data — vehicles interpolated strictly along the
//      decoded polyline coordinates; predictions derived from those positions.
//
//  ──────────────────────────────────────────────────────────────────────────
//  Concurrency design
//  ──────────────────────────────────────────────────────────────────────────
//  • @MainActor final class so all mutable state lives on the main actor and
//    is compatible with every other @MainActor type in the module (PolylineDecoder,
//    Stop.coordinate, response Codable conformances, etc.).
//  • Route detail fetches run in parallel via withThrowingTaskGroup. Each
//    child task calls the `nonisolated static fetchRouteDetail` helper, which
//    owns its own local Decodable response types and JSONDecoder instance to
//    avoid any main-actor isolation inference from APIResponse.swift.
//  • The movement ticker is a detached Task that `await`s back onto the main
//    actor for each tick, using a weak self capture to prevent retain cycles.
//  ──────────────────────────────────────────────────────────────────────────

import Foundation
import CoreLocation

@MainActor
final class CABSHybridService: TransitService {

    // MARK: - Network

    private let baseURL = "https://content.osu.edu/v2/bus/routes"

    // MARK: - Cached Route Geometry

    private struct RouteCache {
        let route: Route
        /// Full decoded coordinate path of the longest pattern.
        let path: [CLLocationCoordinate2D]
        /// Normalized progress delta per 3-second tick for ~40 km/h.
        let stepPerTick: Double
    }

    private var routeCache: [String: RouteCache] = [:]

    // MARK: - Simulated Bus State

    private struct BusState {
        var routeCode: String
        /// Fractional position in [0, 1) along the route's decoded path.
        var normalizedProgress: Double
        var patternID: String
    }

    private var busStates: [String: BusState] = [:]

    // MARK: - Movement Timer

    private var movementTask: Task<Void, Never>?

    // MARK: - Init / Deinit

    init() {
        movementTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                self?.tick()
            }
        }
    }

    deinit {
        movementTask?.cancel()
    }

    // MARK: - TransitService: Real Static Data

    func fetchRoutes() async throws -> [Route] {
        // ── Step 1: fetch route list ──────────────────────────────────────
        let listURL = URL(string: baseURL)!
        let (listData, _) = try await URLSession.shared.data(from: listURL)
        let listResponse = try JSONDecoder().decode(CABSRoutesListResponse.self, from: listData)
        guard let routeInfos = listResponse.data?.routes else { return [] }

        // ── Step 2: fetch all route details in parallel ───────────────────
        // Capture only Sendable strings before entering the task group.
        let capturedBase = baseURL
        let routes = try await withThrowingTaskGroup(of: Route.self) { group in
            for info in routeInfos {
                let code     = info.code
                let colorHex = info.color
                let name     = info.name
                group.addTask {
                    // nonisolated static helper — runs on the cooperative pool,
                    // uses its own local Decodable types, never touches actor state.
                    try await CABSHybridService.fetchRouteDetail(
                        code: code, colorHex: colorHex, name: name,
                        baseURL: capturedBase
                    )
                }
            }
            var collected: [Route] = []
            for try await route in group { collected.append(route) }
            return collected.sorted { $0.id < $1.id }
        }

        // ── Step 3: decode polylines, cache geometry, spawn buses ─────────
        for route in routes {
            let path = longestPath(for: route)     // uses PolylineDecoder — @MainActor OK
            let step = normalizedStep(forPathLength: pathLengthMeters(path))
            routeCache[route.id] = RouteCache(route: route, path: path, stepPerTick: step)

            // Only spawn once — don't reset positions on subsequent loadRoutes calls.
            if busStates["\(route.id)-BUS-1"] == nil {
                spawnBuses(routeCode: route.id, path: path, patternID: route.patterns.first?.id ?? "")
            }
        }

        return routes
    }

    // MARK: - TransitService: Simulated Dynamic Data

    func fetchVehicles(routeCode: String) async throws -> [Bus] {
        guard let cache = routeCache[routeCode], !cache.path.isEmpty else { return [] }
        let path  = cache.path
        let stops = cache.route.stops

        return busStates
            .filter { $0.value.routeCode == routeCode }
            .map { (id, state) in
                let coord   = interpolatedCoordinate(progress: state.normalizedProgress, path: path)
                let heading = interpolatedHeading(progress: state.normalizedProgress, path: path)
                let next    = nearestStop(to: coord, in: stops)
                return Bus(
                    id: id,
                    routeCode: routeCode,
                    latitude: coord.latitude,
                    longitude: coord.longitude,
                    heading: heading,
                    speed: 25,
                    destination: next?.name ?? "En Route",
                    delayed: false,
                    patternId: state.patternID,
                    nextStopID: next?.id,
                    distance: nil,
                    lastUpdated: Date()
                )
            }
    }

    func fetchPredictions(stopID: String) async throws -> [Prediction] {
        var predictions: [Prediction] = []
        let speedMetersPerSecond = 6.7  // ~15 mph campus shuttle speed

        for (_, cache) in routeCache {
            guard let stop = cache.route.stops.first(where: { $0.id == stopID }),
                  !cache.path.isEmpty else { continue }

            let stopLoc      = CLLocation(latitude: stop.latitude, longitude: stop.longitude)
            let stopProgress = nearestProgress(to: stop.coordinate, in: cache.path)
            let totalLength  = pathLengthMeters(cache.path)

            for (busID, state) in busStates where state.routeCode == cache.route.id {
                let busCoord = interpolatedCoordinate(progress: state.normalizedProgress, path: cache.path)
                let busLoc   = CLLocation(latitude: busCoord.latitude, longitude: busCoord.longitude)

                // Forward-aware distance: a bus that just passed the stop must
                // travel the rest of the loop before arriving again.
                let forward = forwardProgress(from: state.normalizedProgress, to: stopProgress)
                let distanceMeters = forward > 0.01
                    ? forward * totalLength              // general case: path-trace distance
                    : busLoc.distance(from: stopLoc)    // near-arrival: straight-line is accurate
                let arrivalSeconds = distanceMeters / speedMetersPerSecond

                predictions.append(Prediction(
                    id: "\(busID)-\(stopID)",
                    routeCode: cache.route.id,
                    vehicleID: busID,
                    stopID: stopID,
                    arrivalSeconds: arrivalSeconds
                ))
            }
        }

        return predictions.sorted { $0.arrivalSeconds < $1.arrivalSeconds }
    }

    // MARK: - Simulation Tick

    private func tick() {
        for key in busStates.keys {
            guard let step = routeCache[busStates[key]!.routeCode]?.stepPerTick else { continue }
            busStates[key]?.normalizedProgress += step
            if (busStates[key]?.normalizedProgress ?? 0) >= 1.0 {
                busStates[key]?.normalizedProgress -= 1.0
            }
        }
    }

    // MARK: - Bus Spawning

    private func spawnBuses(routeCode: String, path: [CLLocationCoordinate2D], patternID: String) {
        guard !path.isEmpty else { return }
        for i in 0..<2 {
            busStates["\(routeCode)-BUS-\(i + 1)"] = BusState(
                routeCode: routeCode,
                normalizedProgress: Double(i) / 2.0,
                patternID: patternID
            )
        }
    }

    // MARK: - Geometry Helpers

    private func longestPath(for route: Route) -> [CLLocationCoordinate2D] {
        route.patterns
            .map { PolylineDecoder.decode($0.encodedPolyline) }
            .max(by: { $0.count < $1.count })
            ?? []
    }

    private func pathLengthMeters(_ path: [CLLocationCoordinate2D]) -> Double {
        guard path.count > 1 else { return 0 }
        var total = 0.0
        for i in 0..<path.count - 1 {
            total += CLLocation(latitude: path[i].latitude, longitude: path[i].longitude)
                .distance(from: CLLocation(latitude: path[i + 1].latitude, longitude: path[i + 1].longitude))
        }
        return total
    }

    /// Normalized progress increment per 3-second tick at 40 km/h.
    /// Falls back to a 10-minute loop when path length is zero.
    private func normalizedStep(forPathLength meters: Double) -> Double {
        guard meters > 0 else { return 3.0 / (10.0 * 60.0) }
        return (40.0 / 3.6 * 3.0) / meters
    }

    private func interpolatedCoordinate(
        progress: Double,
        path: [CLLocationCoordinate2D]
    ) -> CLLocationCoordinate2D {
        guard path.count > 1 else { return path.first ?? CLLocationCoordinate2D() }
        let scaled = max(0, min(1, progress)) * Double(path.count - 1)
        let lower  = Int(scaled)
        let upper  = min(lower + 1, path.count - 1)
        let frac   = scaled - Double(lower)
        let a = path[lower], b = path[upper]
        return CLLocationCoordinate2D(
            latitude:  a.latitude  + (b.latitude  - a.latitude)  * frac,
            longitude: a.longitude + (b.longitude - a.longitude) * frac
        )
    }

    /// Forward tangent of the route at `progress`, taken from the *same*
    /// decoded-polyline segment that `interpolatedCoordinate` places the bus
    /// on — so the arrow tracks the direction of travel, and turns rotate
    /// gradually because the polyline is dense.
    ///
    /// Direction: buses advance `normalizedProgress` forward each tick (see
    /// `tick()`), so the tangent runs from the lower index toward the upper —
    /// the forward heading. Zero-length segments (duplicate polyline points)
    /// are skipped by searching outward for the nearest distinct pair; at the
    /// path tail the last distinct segment behind the bus is reused so the
    /// heading stays forward instead of snapping. Returns `nil` only when the
    /// whole path is degenerate.
    private func interpolatedHeading(
        progress: Double,
        path: [CLLocationCoordinate2D]
    ) -> Double? {
        guard path.count > 1 else { return nil }
        let scaled = max(0, min(1, progress)) * Double(path.count - 1)
        let lower  = min(Int(scaled), path.count - 1)

        // Forward: nearest distinct point ahead of `lower`.
        var upper = lower + 1
        while upper < path.count, RouteGeometry.coincident(path[lower], path[upper]) {
            upper += 1
        }
        if upper < path.count {
            return RouteGeometry.forwardBearing(from: path[lower], to: path[upper])
        }

        // At the tail: reuse the last distinct segment behind the bus, keeping
        // the same forward direction of travel.
        var back = lower - 1
        while back >= 0, RouteGeometry.coincident(path[back], path[lower]) {
            back -= 1
        }
        guard back >= 0 else { return nil }
        return RouteGeometry.forwardBearing(from: path[back], to: path[lower])
    }

    private func nearestStop(to coord: CLLocationCoordinate2D, in stops: [Stop]) -> Stop? {
        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        return stops.min {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: loc) <
            CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: loc)
        }
    }

    private func nearestProgress(to target: CLLocationCoordinate2D, in path: [CLLocationCoordinate2D]) -> Double {
        guard !path.isEmpty else { return 0 }
        let tLoc = CLLocation(latitude: target.latitude, longitude: target.longitude)
        var best = 0, bestDist = CLLocationDistanceMax
        for (i, c) in path.enumerated() {
            let d = CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: tLoc)
            if d < bestDist { bestDist = d; best = i }
        }
        return Double(best) / Double(max(path.count - 1, 1))
    }

    private func forwardProgress(from current: Double, to target: Double) -> Double {
        let diff = target - current
        return diff < 0 ? diff + 1.0 : diff
    }

    // MARK: - Nonisolated Network Helper

    /// Fetches a single route's stops and patterns from the CABS API.
    ///
    /// - `nonisolated static` so child tasks in the withThrowingTaskGroup run
    ///   concurrently on the cooperative thread pool rather than serialising
    ///   through the main actor.
    /// - Uses private local Decodable structs to avoid picking up any @MainActor
    ///   inference that Swift may apply to the shared APIResponse.swift types.
    private nonisolated static func fetchRouteDetail(
        code: String,
        colorHex: String,
        name: String,
        baseURL: String
    ) async throws -> Route {

        // Local response types — isolated from any @MainActor inference.
        struct Envelope: Decodable {
            struct Body: Decodable {
                let stops: [StopPayload]?
                let patterns: [PatternPayload]?
            }
            struct StopPayload: Decodable {
                let id: String?
                let name: String?
                let latitude: Double?
                let longitude: Double?
            }
            struct PatternPayload: Decodable {
                let id: String?
                let direction: String?
                let encodedPolyline: String?
                let length: Int?
            }
            let data: Body?
        }

        let url          = URL(string: "\(baseURL)/\(code)")!
        let (data, _)    = try await URLSession.shared.data(from: url)
        let response     = try JSONDecoder().decode(Envelope.self, from: data)

        let stops = (response.data?.stops ?? []).compactMap { s -> Stop? in
            guard let id  = s.id,   let sName = s.name,
                  let lat = s.latitude, let lng = s.longitude else { return nil }
            return Stop(id: id, name: sName, latitude: lat, longitude: lng)
        }
        let patterns = (response.data?.patterns ?? []).compactMap { p -> RoutePattern? in
            guard let id  = p.id,  let dir  = p.direction,
                  let poly = p.encodedPolyline, let len = p.length else { return nil }
            return RoutePattern(id: id, direction: dir, encodedPolyline: poly, length: len)
        }

        return Route(id: code, name: name, colorHex: colorHex, stops: stops, patterns: patterns)
    }
}
