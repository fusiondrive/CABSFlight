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

    /// Injected user preferences for route visibility filtering
    var userPreferences: UserPreferences?

    // MARK: - Private Properties

    private var pollingTask: Task<Void, Never>?
    private var animationTask: Task<Void, Never>?
    private var targetBuses: [Bus] = []
    private var isTracking = false
    private let pollingInterval: UInt64 = 3_000_000_000 // 3 seconds in nanoseconds
    private let animationDuration: Double = 0.8

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

        buses = mockBuses
        animatedBuses = mockBuses
        targetBuses = mockBuses
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
            let newBuses = try await CABSAPIService.shared.fetchVehicles(routeCode: routeCode)

            // If empty and no buses, don't update (allows mock data to persist)
            if newBuses.isEmpty && buses.isEmpty {
                return
            }

            targetBuses = newBuses
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

    // MARK: - Predictions

    /// Returns nearby buses from all routes that serve the given stop, sorted by distance.
    func predictions(for stop: Stop) -> [ArrivalPrediction] {
        // Step 1: Find which routes serve this stop
        let servingRoutes = allRoutes.filter { route in
            route.stops.contains { $0.id == stop.id }
        }

        // Step 2: Find vehicles heading toward this stop
        var predictions: [ArrivalPrediction] = []

        for route in servingRoutes {
            let routeVehicles = vehicles.filter { $0.routeCode == route.id }

            for bus in routeVehicles {
                let distance = Self.distance(from: bus.coordinate, to: stop.coordinate)

                // Only show buses within ~1 mile (1600 meters)
                if distance < 1600 {
                    predictions.append(ArrivalPrediction(bus: bus, route: route, distance: distance))
                }
            }
        }

        // Step 3: Sort by nearest distance
        return predictions.sorted { $0.distance < $1.distance }
    }

    /// Haversine distance between two coordinates, in meters.
    private static func distance(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let loc1 = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let loc2 = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return loc1.distance(from: loc2)
    }
}

// MARK: - Arrival Prediction

struct ArrivalPrediction: Identifiable {
    var id: String { "\(bus.id)-\(route.id)" }
    let bus: Bus
    let route: Route
    let distance: Double // meters
}

// MARK: - Map Constants

extension BusViewModel {
    /// OSU campus center coordinates
    static let osuCenter = CLLocationCoordinate2D(latitude: 40.0067, longitude: -83.0305)

    /// Default map span for campus view
    static let defaultSpan = 0.025
}
