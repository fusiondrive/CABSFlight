//
//  BusViewModel.swift
//  CABSFlight
//
//  Created by Steve on 2/7/26.
//

import Foundation
import CoreLocation
import Observation
import SwiftUI
import UIKit

/// Observable view model for bus tracking with automatic polling.
/// The data source is fully injectable — pass CABSHybridService (default)
/// during development or a live implementation for production.
@Observable
@MainActor
final class BusViewModel {
    // MARK: - Public Properties

    /// All routes fetched from the service (unfiltered – used by onboarding)
    private(set) var allRoutes: [Route] = []

    /// Live service predictions for the currently selected stop. Updated whenever
    /// a stop is selected and refreshed on every bus polling tick.
    private(set) var currentStopPredictions: [Prediction] = []

    /// Filtered routes based on user preferences (displayed in route chips)
    var routes: [Route] = []

    var selectedRoute: Route?
    var selectedStop: Stop?
    var selectedBus: Bus?
    var selectedVehicle: Bus? {
        get { selectedBus }
        set { selectedBus = newValue }
    }

    /// Latest authoritative vehicle data from the service.
    /// All business logic — ETA prediction, active counts, route filtering,
    /// Live Activity payloads — reads this, never a mid-animation value.
    private(set) var latestBuses: [Bus] = []

    /// Presentation state for the map annotations. Values are the animation
    /// *targets* (assigned inside `withAnimation`, so SwiftUI renders the
    /// in-between positions), plus a continuous unwrapped heading per bus.
    /// Only map annotation views should read this.
    private(set) var displayedBuses: [DisplayedBus] = []

    /// Convenience alias for business-logic consumers.
    var vehicles: [Bus] { latestBuses }

    var isLoading = false
    var error: String?

    /// Injected user preferences for route visibility filtering
    var userPreferences: UserPreferences?

    // MARK: - Private Properties

    private let service: any TransitService
    private var pollingTask: Task<Void, Never>?
    /// Bumped on every lifecycle transition (suspend/resume/stop). In-flight
    /// fetches compare against it before writing state, so a task that was
    /// cancelled or superseded can never write stale data back.
    private var pollingGeneration = 0
    /// Whether the UI currently wants tracking (map on screen). Combined with
    /// scene phase to decide if the polling task should actually run.
    private var isTrackingRequested = false
    private var speedTrackers: [String: BusSpeedTracker] = [:]
    private let pollingInterval: TimeInterval = 3
    /// Bus glide duration: slightly shorter than the polling period so a bus
    /// normally settles before the next update retargets it. If an update
    /// arrives mid-glide, the native animation redirects from the currently
    /// presented position (verified on device in the Phase 1 probe).
    private var busMoveDuration: TimeInterval { pollingInterval * 0.9 }
    /// A target-to-target jump beyond this is a data discontinuity (GPS jump,
    /// stale gap after backgrounding) — applied without animation rather than
    /// masked by a long glide.
    private let maxAnimatedJumpMeters: Double = 300
    private let averageCampusSpeed = 5.5 // meters per second
    private let maxReliableCampusSpeed = 15.0 // meters per second; faster samples are treated as GPS jitter
    // Widened from 150 m: real OSU stop spacing (400–600 m) means buses are
    // legitimately >150 m from the nearest stop mid-segment.
    private let activeRouteGeofenceDistance = 400.0
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

    /// Default init uses the hybrid service (real routes + simulated buses).
    init() {
        self.service = CABSHybridService()
    }

    /// Dependency-injection init for testing or service swap.
    init(service: any TransitService) {
        self.service = service
    }

    // No `deinit` cancellation is needed — see `resumePolling()` for why the
    // polling task neither retains this view model nor outlives it.

    // MARK: - Public Methods

    /// Start tracking buses with automatic polling (map appeared).
    func startTracking() {
        guard !isTrackingRequested else { return }
        isTrackingRequested = true
        Task {
            await loadRoutes()
        }
        resumePolling()
    }

    /// Stop tracking and cancel all tasks (map disappeared).
    func stopTracking() {
        isTrackingRequested = false
        suspendPolling()
    }

    /// Central app-lifecycle hook — the only place polling reacts to scene
    /// phase. On re-activation the first fetch fires immediately and the map
    /// animates from the currently displayed positions to the fresh data; the
    /// path travelled while backgrounded is never replayed.
    func scenePhaseChanged(to phase: ScenePhase) {
        switch phase {
        case .active:
            resumePolling()
        case .inactive, .background:
            suspendPolling()
        @unknown default:
            break
        }
    }

    /// Select a route and fetch its buses
    func selectRoute(_ route: Route) {
        selectedRoute = route
        selectedStop = nil
        selectedVehicle = nil
        currentStopPredictions = []
        clearVehicleState()
        Task {
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
        Task { await refreshStopPredictions() }
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
        currentStopPredictions = []
        clearVehicleState()
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
                clearVehicleState()
            }
        }
    }

    /// Removes all vehicle data and presentation state without animation
    /// (route switches replace content; buses must not fly between routes).
    private func clearVehicleState() {
        latestBuses = []
        displayedBuses = []
        speedTrackers = [:]
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
            allRoutes = try await service.fetchRoutes()
            applyRouteFilter()
            if selectedRoute == nil, let first = routes.first {
                selectedRoute = first
                await fetchBuses()
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func fetchBuses() async {
        guard let routeCode = selectedRoute?.id else { return }
        let generation = pollingGeneration

        do {
            let incomingBuses = try await service.fetchVehicles(routeCode: routeCode)

            // Discard stale results: polling was suspended/resumed or the
            // route was switched while this request was in flight.
            guard generation == pollingGeneration,
                  !Task.isCancelled,
                  routeCode == selectedRoute?.id else { return }

            if incomingBuses.isEmpty && latestBuses.isEmpty { return }

            let newBuses = spatiallyFilteredVehicles(incomingBuses)
            updateSpeedTrackers(with: newBuses)

            if let selectedVehicle, !newBuses.contains(where: { $0.id == selectedVehicle.id }) {
                self.selectedVehicle = nil
            }

            applyVehicleUpdate(newBuses)

            // Refresh stop predictions on every bus tick so ETAs stay current.
            if selectedStop != nil {
                await refreshStopPredictions()
            }

        } catch {
            guard generation == pollingGeneration else { return }
            self.error = error.localizedDescription
        }
    }

    private func refreshStopPredictions() async {
        guard let stop = selectedStop else {
            currentStopPredictions = []
            return
        }
        let generation = pollingGeneration
        do {
            let predictions = try await service.fetchPredictions(stopID: stop.id)
            guard generation == pollingGeneration, stop.id == selectedStop?.id else { return }
            currentStopPredictions = predictions
        } catch {
            guard generation == pollingGeneration else { return }
            currentStopPredictions = []
        }
    }

    // MARK: - Polling Lifecycle

    /// Starts the single polling task if tracking is wanted and none is
    /// running. Fetches immediately on (re)activation — no waiting for the
    /// first cadence tick. Idempotent across repeated `.active` events.
    ///
    /// Lifecycle safety:
    /// - The task captures `[weak self]` and never holds a strong `self` across
    ///   the `await`s. Each tick hops onto the main actor via `pollTick()`,
    ///   which returns after doing its work, so the strong reference is released
    ///   before `Task.sleep` — the view model can deallocate mid-sleep.
    /// - If `self` is gone when the task wakes, `weak self` is `nil` and the
    ///   loop returns. Hence no `deinit` cancellation is required: the task
    ///   cannot keep the view model alive, and it self-terminates once the view
    ///   model is released.
    /// - Cancellation (`suspendPolling`) ends the task promptly because the
    ///   sleep throws `CancellationError`, which we treat as "stop".
    private func resumePolling() {
        guard isTrackingRequested, pollingTask == nil else { return }
        pollingGeneration += 1
        let generation = pollingGeneration

        pollingTask = Task { [weak self, interval = pollingInterval] in
            while !Task.isCancelled {
                // One actor-isolated hop; strong `self` does not escape it.
                guard let shouldContinue = await self?.pollTick(generation: generation),
                      shouldContinue else { return }

                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    // Cancelled during sleep — end immediately, don't loop.
                    return
                }
            }
        }
    }

    /// Performs one polling iteration on the main actor and reports whether the
    /// loop should continue. Returns `false` if this task has been superseded
    /// (generation bumped) or cancelled, so the caller stops without sleeping.
    /// Kept as a discrete method so the driving task holds `self` only for the
    /// duration of the call, never across `Task.sleep`.
    private func pollTick(generation: Int) async -> Bool {
        guard generation == pollingGeneration, !Task.isCancelled else { return false }
        await fetchBuses()
        return generation == pollingGeneration && !Task.isCancelled
    }

    /// Cancels polling and invalidates every in-flight fetch. Displayed buses
    /// deliberately stay where they are — on resume they animate directly to
    /// the next fresh positions.
    private func suspendPolling() {
        pollingGeneration += 1
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Presentation Update

    /// Publishes a fresh vehicle snapshot to both state layers.
    ///
    /// `latestBuses` is always assigned untouched. `displayedBuses` gets the
    /// same targets wrapped in `withAnimation`, so MapKit animates existing
    /// annotations from their currently *presented* positions (native
    /// redirection — verified in the Phase 1 probe). New buses appear in
    /// place (a new identity has no prior position to fly from); vanished
    /// buses are removed immediately, matching existing product behavior.
    private func applyVehicleUpdate(_ newBuses: [Bus]) {
        latestBuses = newBuses

        // Bound the accumulated continuous headings before animating. Folding
        // by whole turns is visually identical (same angle mod 360°) and only
        // happens in the normally-idle window between glides.
        if displayedBuses.contains(where: { ($0.continuousHeading?.magnitude ?? 0) > 720 }) {
            displayedBuses = displayedBuses.map { $0.foldingHeadingByWholeTurns() }
        }

        let previous = Dictionary(displayedBuses.map { ($0.id, $0) },
                                  uniquingKeysWith: { first, _ in first })
        let updated = newBuses.map { bus in
            DisplayedBus(
                bus: bus,
                continuousHeading: DisplayedBus.unwrappedHeading(
                    target: bus.heading,
                    current: previous[bus.id]?.continuousHeading
                )
            )
        }

        let hasMovingBuses = updated.contains { previous[$0.id] != nil }
        let largestJump = updated
            .compactMap { displayed -> Double? in
                guard let prev = previous[displayed.id] else { return nil }
                return CLLocation(latitude: prev.bus.latitude, longitude: prev.bus.longitude)
                    .distance(from: CLLocation(latitude: displayed.bus.latitude,
                                               longitude: displayed.bus.longitude))
            }
            .max() ?? 0

        if !hasMovingBuses
            || largestJump > maxAnimatedJumpMeters
            || UIAccessibility.isReduceMotionEnabled {
            // Reduce Motion: positions update directly — no sustained spatial
            // animation. Large jumps: an honest teleport instead of a glide
            // that would fabricate a path the bus never travelled.
            displayedBuses = updated
        } else {
            withAnimation(.linear(duration: busMoveDuration)) {
                displayedBuses = updated
            }
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

// MARK: - Displayed Bus (Presentation State)

/// Presentation snapshot for one bus annotation on the map.
///
/// `bus` holds the latest model values (the animation *targets*);
/// `continuousHeading` is the unwrapped rotation angle the marker renders.
/// Business logic must read `BusViewModel.latestBuses`, never this type.
struct DisplayedBus: Identifiable, Equatable {
    /// Latest model snapshot for this vehicle.
    let bus: Bus
    /// Continuous, unwrapped heading in degrees. `nil` when the data source
    /// reports no valid heading — the marker then renders without a direction
    /// arrow instead of fabricating one. The value may leave 0..<360 (e.g.
    /// 370°) so SwiftUI always rotates along the shortest arc.
    let continuousHeading: Double?

    var id: String { bus.id }
    var coordinate: CLLocationCoordinate2D { bus.coordinate }

    /// Unwraps `target` onto the current continuous angle: picks the
    /// equivalent angle nearest the presented one, so 350°→10° advances +20°
    /// (never −340°) and 10°→350° goes back −20°.
    ///
    /// - When `target` is `nil` (heading missing this tick) the last valid
    ///   continuous heading is held, keeping the marker stable.
    /// - When `current` is `nil` (new bus, or one that reappeared and was
    ///   treated as a new instance) the normalized target is used directly —
    ///   no stale angle base is carried over.
    static func unwrappedHeading(target: Double?, current: Double?) -> Double? {
        guard let target else { return current }
        guard let current else { return normalizedAngle(target) }
        var delta = (normalizedAngle(target) - current).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return current + delta
    }

    /// Folds the continuous heading back toward zero by whole turns.
    /// A whole-turn shift renders identically (same angle mod 360°), so this
    /// is safe as a non-animated write; it keeps the accumulated value bounded
    /// over long sessions.
    func foldingHeadingByWholeTurns() -> DisplayedBus {
        guard let heading = continuousHeading, heading.magnitude > 720 else { return self }
        let folded = heading - (heading / 360).rounded(.towardZero) * 360
        return DisplayedBus(bus: bus, continuousHeading: folded)
    }

    private static func normalizedAngle(_ angle: Double) -> Double {
        let remainder = angle.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }
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
