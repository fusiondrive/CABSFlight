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
    
    var routes: [Route] = []
    var selectedRoute: Route?
    var selectedBus: Bus?
    var buses: [Bus] = []
    var animatedBuses: [Bus] = []
    var isLoading = false
    var error: String?
    
    // MARK: - Private Properties
    
    private var pollingTask: Task<Void, Never>?
    private var animationTask: Task<Void, Never>?
    private var targetBuses: [Bus] = []
    private let pollingInterval: UInt64 = 3_000_000_000 // 3 seconds in nanoseconds
    private let animationDuration: Double = 0.8
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Public Methods
    
    /// Start tracking buses with automatic polling
    func startTracking() {
        Task {
            await loadRoutes()
        }
        startPolling()
    }
    
    /// Stop tracking and cancel all tasks
    func stopTracking() {
        pollingTask?.cancel()
        pollingTask = nil
        animationTask?.cancel()
        animationTask = nil
    }
    
    /// Select a route and fetch its buses and route details
    func selectRoute(_ route: Route) {
        selectedRoute = route
        selectedBus = nil
        buses = []
        animatedBuses = []
        Task {
            await fetchRouteDetails(code: route.id)
            await fetchBuses()
        }
    }
    
    /// Select a specific bus to show in the info card
    func selectBus(_ bus: Bus) {
        selectedBus = bus
    }
    
    /// Clear bus selection
    func clearBusSelection() {
        selectedBus = nil
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
            routes = try await CABSAPIService.shared.fetchAllRoutes()
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
            // Also update in routes array
            if let index = routes.firstIndex(where: { $0.id == code }) {
                routes[index] = detailedRoute
            }
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
}

// MARK: - Map Constants

extension BusViewModel {
    /// OSU campus center coordinates
    static let osuCenter = CLLocationCoordinate2D(latitude: 40.0067, longitude: -83.0305)
    
    /// Default map span for campus view
    static let defaultSpan = 0.025
}
