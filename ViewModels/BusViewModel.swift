//
//  BusViewModel.swift
//  CABSFlight
//
//  Created by Steve on 2/7/26.
//

import Foundation
import CoreLocation
import Observation

/// Observable view model for bus tracking with automatic polling
@Observable
@MainActor
final class BusViewModel {
    // MARK: - Public Properties

    /// All routes fetched from API (unfiltered – used by onboarding)
    private(set) var allRoutes: [Route] = []

    /// Filtered routes based on user preferences (displayed in route chips)
    var routes: [Route] = []

    var selectedRoute: Route?
    var selectedStop: Stop?
    var selectedBus: Bus?
    var selectedVehicle: Bus? {
        get { selectedBus }
        set { selectedBus = newValue }
    }
    var vehicles: [Bus] { buses.isEmpty ? animatedBuses : buses }
    var buses: [Bus] = []
    var animatedBuses: [Bus] = []
    var isLoading = false
    var error: String?

    /// When true the production polling loop will discard empty API responses,
    /// protecting any mock buses loaded via loadMockData() from being wiped.
    /// Automatically set by loadMockData(); reset by deselectRoute().
    var mockModeActive: Bool = false

    /// Injected user preferences for route visibility filtering
    var userPreferences: UserPreferences?

    // MARK: - Private Properties

    private var pollingTask: Task<Void, Never>?
    private var animationTask: Task<Void, Never>?
    private var targetBuses: [Bus] = []
    private var speedTrackers: [String: BusSpeedTracker] = [:]
    private var isTracking = false
    private let pollingInterval: UInt64 = 3_000_000_000 // 3 seconds in nanoseconds
    private let animationDuration: Double = 0.8
    private let averageCampusSpeed = 5.5 // meters per second
    private let maxReliableCampusSpeed = 15.0 // meters per second; faster samples are treated as GPS jitter
    private let activeRouteGeofenceDistance = 150.0
    private let averageTimeBetweenStops = 90.0
    private let stationarySpeedThreshold = 1.5
    private let parkedTimeout: TimeInterval = 180
    private let significantMovementDistance = 15.0
    private let routeCorridorDistance = 100.0
    private let depotClusterRadius = 80.0
    private let depotRouteDistanceThreshold = 600.0
    private let headingUpdateDistance = 5.0
    private let stableBearingSpeedThreshold = 2.5
    private let backwardDistanceDecreaseThreshold = 2.0
    private let passByDistance = 15.0
    private let passByAngle = 120.0
    private let shortHopStopLimit = 2
    private let shortHopMaxETASeconds = 15 * 60.0
    private let maxPredictionsPerRoute = 2

    // MARK: - Initialization

    init() {}

    // MARK: - Public Methods

    /// Start tracking buses with automatic polling
    func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        Task {
            await loadRoutes()
        }
        startPolling()
    }

    /// Stop tracking and cancel all tasks
    func stopTracking() {
        isTracking = false
        pollingTask?.cancel()
        pollingTask = nil
        animationTask?.cancel()
        animationTask = nil
    }

    /// Select a route and fetch its buses and route details
    func selectRoute(_ route: Route) {
        selectedRoute = route
        selectedStop = nil
        selectedVehicle = nil
        buses = []
        animatedBuses = []
        speedTrackers = [:]
        Task {
            await fetchRouteDetails(code: route.id)
            await fetchBuses()
        }
    }

    /// Select a specific bus to show in the info card
    func selectBus(_ bus: Bus) {
        selectedStop = nil
        selectedVehicle = bus
    }

    /// Select a specific stop and clear vehicle focus
    func selectStop(_ stop: Stop) {
        selectedStop = stop
        selectedVehicle = nil
    }

    /// Clear bus selection
    func clearBusSelection() {
        selectedVehicle = nil
    }

    /// Deselect the current route, clearing all bus/stop data from the map
    func deselectRoute() {
        selectedRoute = nil
        selectedStop = nil
        selectedVehicle = nil
        buses = []
        animatedBuses = []
        speedTrackers = [:]
        mockModeActive = false   // re-enable live polling for the next route selection
    }

    /// Re-filter `routes` from `allRoutes` using current user preferences.
    /// Call this after preferences change (e.g., after onboarding finishes).
    func applyRouteFilter() {
        if let prefs = userPreferences, !prefs.visibleRouteIDs.isEmpty {
            routes = allRoutes.filter { prefs.isRouteVisible(id: $0.id) }
        } else {
            routes = allRoutes
        }

        // If the currently selected route is no longer visible, switch
        if let selected = selectedRoute, !routes.contains(where: { $0.id == selected.id }) {
            if let first = routes.first {
                selectRoute(first)
            } else {
                selectedRoute = nil
                buses = []
                animatedBuses = []
                speedTrackers = [:]
            }
        }
    }

    /// Load mock data for testing (useful when API returns empty at night)
    func loadMockData() {
        let mockBuses: [Bus] = [
            Bus(
                id: "MOCK-001",
                routeCode: selectedRoute?.id ?? "CLN",
                latitude: 40.0020,
                longitude: -83.0150,
                heading: 45,
                speed: 25,
                destination: "NORTH CAMPUS",
                delayed: false,
                patternId: "314",
                nextStopID: nil,
                distance: 1500,
                lastUpdated: Date()
            ),
            Bus(
                id: "MOCK-002",
                routeCode: selectedRoute?.id ?? "CLN",
                latitude: 40.0055,
                longitude: -83.0280,
                heading: 180,
                speed: 15,
                destination: "SOUTH CAMPUS",
                delayed: false,
                patternId: "429",
                nextStopID: nil,
                distance: 2800,
                lastUpdated: Date()
            ),
            Bus(
                id: "MOCK-003",
                routeCode: selectedRoute?.id ?? "CLN",
                latitude: 39.9985,
                longitude: -83.0380,
                heading: 270,
                speed: 30,
                destination: "WEST CAMPUS",
                delayed: true,
                patternId: "314",
                nextStopID: nil,
                distance: 4200,
                lastUpdated: Date()
            )
        ]

        updateSpeedTrackers(with: mockBuses)
        buses = mockBuses
        animatedBuses = mockBuses
        targetBuses = mockBuses
        // Protect mock positions from being wiped by the next empty API poll.
        mockModeActive = true
    }

    /// Estimated speed in miles per hour, derived from raw coordinate polling.
    func estimatedSpeedMPH(for bus: Bus) -> Int {
        guard let speed = trackedSpeed(for: bus) else { return 0 }
        return Int((speed * 2.2369362921).rounded())
    }

    // MARK: - Private Methods

    private func loadRoutes() async {
        isLoading = true
        error = nil

        do {
            allRoutes = try await CABSAPIService.shared.fetchAllRoutes()
            applyRouteFilter()
            if selectedRoute == nil, let first = routes.first {
                selectedRoute = first
                await fetchRouteDetails(code: first.id)
                await fetchBuses()
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func fetchRouteDetails(code: String) async {
        do {
            let detailedRoute = try await CABSAPIService.shared.fetchRouteDetails(code: code)
            // Update the selected route with patterns and stops
            selectedRoute = detailedRoute
            // Update in allRoutes array
            if let index = allRoutes.firstIndex(where: { $0.id == code }) {
                allRoutes[index] = detailedRoute
            }
            applyRouteFilter()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func fetchBuses() async {
        guard let routeCode = selectedRoute?.id else { return }

        do {
            let incomingBuses = try await CABSAPIService.shared.fetchVehicles(routeCode: routeCode)

            // Mock-mode guard: the mock engine owns all bus state while active.
            // An empty production response must never overwrite simulated positions.
            if mockModeActive && incomingBuses.isEmpty { return }

            // Live-mode guard: nothing on server + nothing on map → no-op.
            if incomingBuses.isEmpty && buses.isEmpty { return }

            let newBuses = spatiallyFilteredVehicles(incomingBuses)

            updateSpeedTrackers(with: newBuses)
            targetBuses = newBuses
            buses = newBuses
            if let selectedVehicle, !newBuses.contains(where: { $0.id == selectedVehicle.id }) {
                self.selectedVehicle = nil
            }

            if newBuses.isEmpty {
                animationTask?.cancel()
                buses = []
                animatedBuses = []
                return
            }

            await animateToBuses(newBuses)

        } catch {
            self.error = error.localizedDescription
        }
    }

    private func startPolling() {
        pollingTask?.cancel()

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchBuses()

                do {
                    try await Task.sleep(nanoseconds: self?.pollingInterval ?? 3_000_000_000)
                } catch {
                    break // Task was cancelled
                }
            }
        }
    }

    private func animateToBuses(_ newBuses: [Bus]) async {
        animationTask?.cancel()

        let startBuses = animatedBuses.isEmpty ? newBuses : animatedBuses
        let startTime = Date()

        animationTask = Task { [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startTime)
                let progress = min(elapsed / self.animationDuration, 1.0)

                // Ease-out cubic
                let easedProgress = 1 - pow(1 - progress, 3)

                self.animatedBuses = self.interpolateBuses(
                    from: startBuses,
                    to: newBuses,
                    progress: easedProgress
                )

                if progress >= 1.0 {
                    self.buses = newBuses
                    self.animatedBuses = newBuses
                    break
                }

                // ~60 FPS
                try? await Task.sleep(nanoseconds: 16_666_667)
            }
        }
    }

    private func interpolateBuses(from: [Bus], to: [Bus], progress: Double) -> [Bus] {
        to.map { targetBus in
            if let sourceBus = from.first(where: { $0.id == targetBus.id }) {
                return sourceBus.interpolated(to: targetBus, progress: progress)
            }
            return targetBus
        }
    }

    // MARK: - Speed Tracking

    private func updateSpeedTrackers(with newBuses: [Bus], at updateTime: Date = Date()) {
        var activeKeys = Set<String>()

        for bus in newBuses {
            let key = speedTrackerKey(for: bus)
            activeKeys.insert(key)
            let currentLocation = CLLocation(latitude: bus.latitude, longitude: bus.longitude)
            var tracker = speedTrackers[key] ?? BusSpeedTracker()

            guard let lastLocation = tracker.lastLocation,
                  let lastUpdateTime = tracker.lastUpdateTime else {
                tracker.lastLocation = currentLocation
                tracker.previousLocation = nil
                tracker.lastSignificantLocation = currentLocation
                tracker.lastUpdateTime = updateTime
                tracker.stationarySince = updateTime
                speedTrackers[key] = tracker
                continue
            }

            let distance = currentLocation.distance(from: lastLocation)
            let timeDelta = updateTime.timeIntervalSince(lastUpdateTime)
            let inferredSpeed = distance / timeDelta

            guard inferredSpeed.isFinite, inferredSpeed >= 0 else {
                tracker.inferredSpeed = nil
                speedTrackers[key] = tracker
                continue
            }

            guard inferredSpeed <= maxReliableCampusSpeed else {
                // Treat large coordinate jumps as GPS jitter. Keep the previous stable sample.
                speedTrackers[key] = tracker
                continue
            }

            tracker.inferredSpeed = inferredSpeed
            if inferredSpeed > stableBearingSpeedThreshold, distance >= headingUpdateDistance {
                tracker.stableBearing = bearing(
                    from: lastLocation.coordinate,
                    to: currentLocation.coordinate
                )
            }
            tracker.previousLocation = lastLocation
            tracker.lastLocation = currentLocation
            tracker.lastUpdateTime = updateTime

            let significantLocation = tracker.lastSignificantLocation ?? lastLocation
            let movedSignificantly = currentLocation.distance(from: significantLocation) >= significantMovementDistance
            if movedSignificantly {
                tracker.lastSignificantLocation = currentLocation
                tracker.stationarySince = nil
            } else if inferredSpeed < stationarySpeedThreshold, tracker.stationarySince == nil {
                tracker.stationarySince = updateTime
            }

            speedTrackers[key] = tracker
        }

        speedTrackers = speedTrackers.filter { activeKeys.contains($0.key) }
    }

    private func trackedSpeed(for bus: Bus) -> Double? {
        guard let speed = speedTrackers[speedTrackerKey(for: bus)]?.inferredSpeed,
              speed.isFinite,
              speed >= 0 else {
            return nil
        }

        return speed
    }

    private func inferredSpeed(for bus: Bus) -> Double {
        trackedSpeed(for: bus) ?? averageCampusSpeed
    }

    private func stableLocation(for bus: Bus) -> CLLocation {
        speedTrackers[speedTrackerKey(for: bus)]?.lastLocation
            ?? CLLocation(latitude: bus.latitude, longitude: bus.longitude)
    }

    private func speedTrackerKey(for bus: Bus) -> String {
        "\(bus.routeCode)-\(bus.id)"
    }

    // MARK: - Spatial Filtering

    private func spatiallyFilteredVehicles(_ incomingBuses: [Bus]) -> [Bus] {
        incomingBuses.filter { bus in
            guard let route = route(for: bus),
                  !route.stops.isEmpty else {
                return true
            }

            return currentRouteStopDistance(for: bus, route: route) <= activeRouteGeofenceDistance
        }
    }

    private func route(for bus: Bus) -> Route? {
        if selectedRoute?.id == bus.routeCode {
            return selectedRoute
        }

        return allRoutes.first { $0.id == bus.routeCode }
    }

    private func currentRouteStopDistance(for bus: Bus, route: Route) -> Double {
        let busLocation = CLLocation(latitude: bus.latitude, longitude: bus.longitude)
        return nearestRouteStopDistance(from: busLocation, route: route)
    }

    // MARK: - Predictions

    /// Returns predicted arrivals for a stop using route sequence order and inactive bus filtering.
    func predictions(for targetStop: Stop) -> [ArrivalPrediction] {
        // 1. Identify routes serving this stop
        let servingRoutes = allRoutes.filter { route in
            route.stops.contains { $0.id == targetStop.id }
        }

        var predictions: [ArrivalPrediction] = []

        for route in servingRoutes {
            // Ordered stop IDs for "stops away" calculation
            let routeStopIDs = route.stops.map { $0.id }
            guard let targetIndex = routeStopIDs.firstIndex(of: targetStop.id) else { continue }

            predictions.append(contentsOf: predictionCandidates(
                for: route,
                targetIndex: targetIndex
            ))
        }

        // Sort by soonest arrival first
        return predictions.sorted { $0.rawSeconds < $1.rawSeconds }
    }

    private func predictionCandidates(
        for route: Route,
        targetIndex: Int
    ) -> [ArrivalPrediction] {
        let routeVehicles = vehicles.filter { $0.routeCode == route.id }
        guard !routeVehicles.isEmpty else { return [] }

        let metrics = routeVehicles.map { bus in
            PredictionVehicleMetric(
                bus: bus,
                nearestRouteStopDistance: nearestRouteStopDistance(for: bus, route: route),
                routeAnchor: routeAnchor(for: bus, route: route),
                isOffRouteCluster: isOffRouteCluster(for: bus, route: route, routeVehicles: routeVehicles),
                isParkedTooLong: isParkedTooLong(bus),
                isMoving: (trackedSpeed(for: bus) ?? 0) >= stationarySpeedThreshold
            )
        }

        let protectedBusID = protectedServingBusID(from: metrics)
        let movingMetricsCount = metrics.filter(\.isMoving).count
        let allowStationaryPrediction = routeVehicles.count == 1 || movingMetricsCount == 0
        let predictions = metrics.compactMap { metric -> PredictionCandidate? in
            guard metric.nearestRouteStopDistance <= activeRouteGeofenceDistance else { return nil }
            guard metric.isMoving || allowStationaryPrediction else { return nil }
            guard let routeAnchor = metric.routeAnchor else { return nil }
            guard !metric.isOffRouteCluster else { return nil }
            if metric.isParkedTooLong, metric.bus.id != protectedBusID {
                return nil
            }

            guard let eta = calculateETA(
                for: metric.bus,
                route: route,
                targetIndex: targetIndex,
                routeAnchor: routeAnchor
            ) else { return nil }

            return PredictionCandidate(
                prediction: ArrivalPrediction(
                    bus: metric.bus,
                    route: route,
                    timeDisplay: eta.display,
                    rawSeconds: eta.rawSeconds
                ),
                isProtected: metric.bus.id == protectedBusID,
                isMoving: metric.isMoving,
                stabilityScore: stabilityScore(
                    for: metric,
                    routeAnchor: routeAnchor,
                    movingMetricsCount: movingMetricsCount
                ),
                nearestRouteStopDistance: metric.nearestRouteStopDistance
            )
        }

        return predictions
            .sorted(by: shouldSortBefore)
            .prefix(maxPredictionsPerRoute)
            .map(\.prediction)
    }

    private func protectedServingBusID(from metrics: [PredictionVehicleMetric]) -> String? {
        let routeServingMetrics = metrics.filter {
            !$0.isOffRouteCluster && $0.nearestRouteStopDistance <= activeRouteGeofenceDistance
        }

        if routeServingMetrics.count == 1 {
            return routeServingMetrics[0].bus.id
        }

        let movingMetrics = routeServingMetrics.filter(\.isMoving)
        if movingMetrics.count == 1 {
            return movingMetrics[0].bus.id
        }

        return nil
    }

    private func shouldSortBefore(_ lhs: PredictionCandidate, _ rhs: PredictionCandidate) -> Bool {
        if lhs.isProtected != rhs.isProtected {
            return lhs.isProtected
        }

        if lhs.isMoving != rhs.isMoving {
            return lhs.isMoving
        }

        if lhs.stabilityScore != rhs.stabilityScore {
            return lhs.stabilityScore > rhs.stabilityScore
        }

        if lhs.prediction.rawSeconds != rhs.prediction.rawSeconds {
            return lhs.prediction.rawSeconds < rhs.prediction.rawSeconds
        }

        return lhs.nearestRouteStopDistance < rhs.nearestRouteStopDistance
    }

    private func stabilityScore(
        for metric: PredictionVehicleMetric,
        routeAnchor: BusRouteAnchor,
        movingMetricsCount: Int
    ) -> Int {
        var score = 0

        if metric.isMoving {
            score += 100
        } else if movingMetricsCount == 0 {
            score += 1
        }

        if routeAnchor.isHysteresisStable {
            score += 40
        }

        if metric.isParkedTooLong {
            score -= 100
        }

        score -= min(Int(metric.nearestRouteStopDistance / 10), 20)
        return score
    }

    private func nearestRouteStopDistance(for bus: Bus, route: Route) -> Double {
        nearestRouteStopDistance(from: stableLocation(for: bus), route: route)
    }

    private func nearestRouteStopDistance(from busLocation: CLLocation, route: Route) -> Double {
        return route.stops
            .map { busLocation.distance(from: location(for: $0)) }
            .min() ?? .greatestFiniteMagnitude
    }

    private func isOffRouteCluster(for bus: Bus, route: Route, routeVehicles: [Bus]) -> Bool {
        let nearestStopDistance = nearestRouteStopDistance(for: bus, route: route)
        guard nearestStopDistance > depotRouteDistanceThreshold else { return false }

        let busLocation = stableLocation(for: bus)
        return routeVehicles.contains { otherBus in
            guard otherBus.id != bus.id else { return false }
            return busLocation.distance(from: stableLocation(for: otherBus)) <= depotClusterRadius
        }
    }

    private func isParkedTooLong(_ bus: Bus, at currentTime: Date = Date()) -> Bool {
        guard let tracker = speedTrackers[speedTrackerKey(for: bus)],
              let stationarySince = tracker.stationarySince else {
            return false
        }

        let speed = tracker.inferredSpeed ?? 0
        return speed < stationarySpeedThreshold
            && currentTime.timeIntervalSince(stationarySince) >= parkedTimeout
    }

    private func calculateETA(
        for bus: Bus,
        route: Route,
        targetIndex: Int,
        routeAnchor: BusRouteAnchor
    ) -> ETAResult? {
        guard let upcomingStop = stop(at: routeAnchor.upcomingIndex, in: route),
              route.stops.indices.contains(targetIndex) else {
            return nil
        }

        let stopsToTravel = stopsToTravel(
            from: routeAnchor.upcomingIndex,
            to: targetIndex,
            stopCount: route.stops.count,
            isBackward: routeAnchor.isBackward
        )
        let currentLocation = stableLocation(for: bus)
        let timeToNext = currentLocation.distance(from: location(for: upcomingStop))
            / max(inferredSpeed(for: bus), averageCampusSpeed)
        let timeForRest = Double(stopsToTravel) * averageTimeBetweenStops
        let totalSeconds = timeToNext + timeForRest
        guard totalSeconds.isFinite, totalSeconds >= 0 else { return nil }
        if stopsToTravel <= shortHopStopLimit && totalSeconds > shortHopMaxETASeconds {
            return nil
        }

        let isDue = stopsToTravel == 0 && timeToNext < 60
        return formatETA(seconds: totalSeconds, isDue: isDue)
    }

    private func routeAnchor(for bus: Bus, route: Route) -> BusRouteAnchor? {
        let count = route.stops.count
        guard count > 0 else { return nil }
        guard let stableBearing = stableBearing(for: bus) else { return nil }

        let busLocation = stableLocation(for: bus)
        var bestAnchor: AnchorCandidate?
        var minDistance = CLLocationDistance.greatestFiniteMagnitude

        for (index, stop) in route.stops.enumerated() {
            let nextIndex = moduloIndex(index + 1, count: count)
            let previousIndex = moduloIndex(index - 1, count: count)
            guard let nextStop = self.stop(at: nextIndex, in: route),
                  let previousStop = self.stop(at: previousIndex, in: route) else { continue }

            let forwardBearing = bearing(from: stop.coordinate, to: nextStop.coordinate)
            let backwardBearing = bearing(from: stop.coordinate, to: previousStop.coordinate)
            let forwardDiff = angleDelta(from: stableBearing, to: forwardBearing)
            let backwardDiff = angleDelta(from: stableBearing, to: backwardBearing)
            let isForwardAligned = forwardDiff < 90
            let isBackwardAligned = backwardDiff < 90
            guard isForwardAligned || isBackwardAligned else { continue }

            let distance = busLocation.distance(from: location(for: stop))
            if distance < minDistance {
                minDistance = distance
                bestAnchor = AnchorCandidate(
                    index: index,
                    isBackward: isBackwardAligned && (!isForwardAligned || backwardDiff < forwardDiff)
                )
            }
        }

        guard let alignedAnchor = bestAnchor,
              minDistance <= routeCorridorDistance,
              let alignedStop = stop(at: alignedAnchor.index, in: route) else {
            return nil
        }

        var isBackward = alignedAnchor.isBackward
        if isBackward,
           !isBackwardDirectionConsistent(for: bus, from: alignedAnchor.index, route: route) {
            isBackward = false
        }

        var upcomingIndex = alignedAnchor.index
        let bearingToStop = bearing(from: busLocation.coordinate, to: alignedStop.coordinate)
        let angleDiff = angleDelta(from: stableBearing, to: bearingToStop)
        if angleDiff > passByAngle && minDistance > passByDistance {
            upcomingIndex = nextStopIndex(
                from: alignedAnchor.index,
                stopCount: count,
                isBackward: isBackward
            )
        }

        let hysteresisResult = applyAnchorHysteresis(
            for: bus,
            candidateIndex: upcomingIndex,
            stopCount: count,
            isBackward: isBackward
        )
        upcomingIndex = hysteresisResult.upcomingIndex

        guard stop(at: upcomingIndex, in: route) != nil else { return nil }
        return BusRouteAnchor(
            upcomingIndex: upcomingIndex,
            isBackward: isBackward,
            isHysteresisStable: hysteresisResult.isStable
        )
    }

    private func applyAnchorHysteresis(
        for bus: Bus,
        candidateIndex: Int,
        stopCount: Int,
        isBackward: Bool,
        at currentTime: Date = Date()
    ) -> AnchorHysteresisResult {
        guard stopCount > 0 else {
            return AnchorHysteresisResult(upcomingIndex: 0, isStable: false)
        }

        let key = speedTrackerKey(for: bus)
        let normalizedCandidate = moduloIndex(candidateIndex, count: stopCount)
        guard var tracker = speedTrackers[key] else {
            return AnchorHysteresisResult(upcomingIndex: normalizedCandidate, isStable: false)
        }

        if let stationarySince = tracker.stationarySince,
           currentTime.timeIntervalSince(stationarySince) >= parkedTimeout {
            tracker.lastUpcomingIndex = normalizedCandidate
            speedTrackers[key] = tracker
            return AnchorHysteresisResult(upcomingIndex: normalizedCandidate, isStable: false)
        }

        guard let previousIndex = tracker.lastUpcomingIndex else {
            tracker.lastUpcomingIndex = normalizedCandidate
            speedTrackers[key] = tracker
            return AnchorHysteresisResult(upcomingIndex: normalizedCandidate, isStable: false)
        }

        let normalizedPrevious = moduloIndex(previousIndex, count: stopCount)
        let directionalDistance = directionalStopDistance(
            from: normalizedPrevious,
            to: normalizedCandidate,
            stopCount: stopCount,
            isBackward: isBackward
        )

        let acceptedIndex: Int
        if directionalDistance <= 2 {
            acceptedIndex = normalizedCandidate
        } else {
            acceptedIndex = normalizedPrevious
        }

        tracker.lastUpcomingIndex = acceptedIndex
        speedTrackers[key] = tracker
        return AnchorHysteresisResult(upcomingIndex: acceptedIndex, isStable: true)
    }

    private func directionalStopDistance(
        from startIndex: Int,
        to endIndex: Int,
        stopCount: Int,
        isBackward: Bool
    ) -> Int {
        guard stopCount > 0 else { return 0 }
        if isBackward {
            return moduloIndex(startIndex - endIndex, count: stopCount)
        }

        return moduloIndex(endIndex - startIndex, count: stopCount)
    }

    private func isBackwardDirectionConsistent(for bus: Bus, from index: Int, route: Route) -> Bool {
        let count = route.stops.count
        guard count > 0,
              let speed = trackedSpeed(for: bus),
              speed >= stableBearingSpeedThreshold,
              let previousLocation = speedTrackers[speedTrackerKey(for: bus)]?.previousLocation else {
            return false
        }

        let nextBackwardIndex = moduloIndex(index - 1, count: count)
        guard let nextBackwardStop = stop(at: nextBackwardIndex, in: route) else { return false }

        let stopLocation = location(for: nextBackwardStop)
        let currentDistance = stableLocation(for: bus).distance(from: stopLocation)
        let previousDistance = previousLocation.distance(from: stopLocation)
        return previousDistance - currentDistance >= backwardDistanceDecreaseThreshold
    }

    private func nextStopIndex(
        from index: Int,
        stopCount: Int,
        isBackward: Bool
    ) -> Int {
        guard stopCount > 0 else { return 0 }
        return moduloIndex(index + (isBackward ? -1 : 1), count: stopCount)
    }

    private func stopsToTravel(
        from upcomingIndex: Int,
        to targetIndex: Int,
        stopCount: Int,
        isBackward: Bool
    ) -> Int {
        guard stopCount > 0 else { return 0 }
        if isBackward {
            return moduloIndex(upcomingIndex - targetIndex, count: stopCount)
        }

        return moduloIndex(targetIndex - upcomingIndex, count: stopCount)
    }

    private func moduloIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let remainder = index % count
        return remainder >= 0 ? remainder : remainder + count
    }

    private func formatETA(seconds totalSeconds: Double, isDue: Bool) -> ETAResult {
        guard totalSeconds.isFinite, totalSeconds >= 0 else {
            return ETAResult(display: "Due", rawSeconds: 0)
        }

        if isDue {
            return ETAResult(display: "Due", rawSeconds: totalSeconds)
        }

        let minutes = max(1, Int(ceil(totalSeconds / 60)))
        return ETAResult(display: "\(minutes) min", rawSeconds: totalSeconds)
    }

    private func stableBearing(for bus: Bus) -> Double? {
        speedTrackers[speedTrackerKey(for: bus)]?.stableBearing
    }

    private func stop(at index: Int, in route: Route) -> Stop? {
        guard route.stops.indices.contains(index) else { return nil }
        return route.stops[index]
    }

    private func location(for stop: Stop) -> CLLocation {
        CLLocation(latitude: stop.latitude, longitude: stop.longitude)
    }

    private func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let longitudeDelta = (end.longitude - start.longitude) * .pi / 180

        let y = sin(longitudeDelta) * cos(endLatitude)
        let x = cos(startLatitude) * sin(endLatitude)
            - sin(startLatitude) * cos(endLatitude) * cos(longitudeDelta)
        let degrees = atan2(y, x) * 180 / .pi
        return normalizedHeading(degrees)
    }

    private func angleDelta(from heading: Double, to bearing: Double) -> Double {
        let delta = abs(normalizedHeading(heading) - normalizedHeading(bearing))
        return min(delta, 360 - delta)
    }

    private func normalizedHeading(_ heading: Double) -> Double {
        let normalized = heading.truncatingRemainder(dividingBy: 360)
        return normalized >= 0 ? normalized : normalized + 360
    }
}

private struct BusSpeedTracker {
    var lastLocation: CLLocation?
    var previousLocation: CLLocation?
    var lastSignificantLocation: CLLocation?
    var lastUpdateTime: Date?
    var stationarySince: Date?
    var inferredSpeed: Double?
    var stableBearing: Double?
    var lastUpcomingIndex: Int?
}

private struct ETAResult {
    let display: String
    let rawSeconds: Double
}

private struct BusRouteAnchor {
    let upcomingIndex: Int
    let isBackward: Bool
    let isHysteresisStable: Bool
}

private struct AnchorCandidate {
    let index: Int
    let isBackward: Bool
}

private struct AnchorHysteresisResult {
    let upcomingIndex: Int
    let isStable: Bool
}

private struct PredictionVehicleMetric {
    let bus: Bus
    let nearestRouteStopDistance: Double
    let routeAnchor: BusRouteAnchor?
    let isOffRouteCluster: Bool
    let isParkedTooLong: Bool
    let isMoving: Bool
}

private struct PredictionCandidate {
    let prediction: ArrivalPrediction
    let isProtected: Bool
    let isMoving: Bool
    let stabilityScore: Int
    let nearestRouteStopDistance: Double
}

// MARK: - Arrival Prediction

struct ArrivalPrediction: Identifiable {
    var id: String { "\(bus.id)-\(route.id)" }
    let bus: Bus
    let route: Route
    let timeDisplay: String  // "Due" or "N min"
    let rawSeconds: Double   // Total estimated seconds for sorting
}

// MARK: - Map Constants

extension BusViewModel {
    /// OSU campus center coordinates
    static let osuCenter = CLLocationCoordinate2D(latitude: 40.0067, longitude: -83.0305)

    /// Default map span for campus view
    static let defaultSpan = 0.025
}
