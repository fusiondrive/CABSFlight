//
//  BusTrackingViewModel.swift
//  CABSFlight
//
//  Created by Steve on 2/7/26.
//

import Foundation
import Combine
import CoreLocation

/// Main view model for bus tracking with live updates
@MainActor
class BusTrackingViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var routes: [Route] = []
    @Published var selectedRoute: Route?
    @Published var buses: [Bus] = []
    @Published var isLoading = false
    @Published var error: String?
    
    // For smooth animations - previous positions
    @Published private(set) var animatedBuses: [Bus] = []
    
    // MARK: - Private Properties
    
    private var updateTimer: Timer?
    private var animationTimer: Timer?
    private var targetBuses: [Bus] = []
    private var animationProgress: Double = 0
    private let updateInterval: TimeInterval = 5.0
    private let animationDuration: TimeInterval = 1.0
    
    // MARK: - Initialization
    
    init() {
        // Select first route by default
        selectedRoute = routes.first
    }
    
    // MARK: - Public Methods
    
    func startTracking() {
        Task {
            await loadRoutes()
            await fetchBuses()
        }
        
        // Set up periodic updates
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchBuses()
            }
        }
    }
    
    func stopTracking() {
        updateTimer?.invalidate()
        updateTimer = nil
        animationTimer?.invalidate()
        animationTimer = nil
    }
    
    func selectRoute(_ route: Route) {
        selectedRoute = route
        buses = []
        animatedBuses = []
        Task {
            await fetchBuses()
        }
    }
    
    // MARK: - Private Methods
    
    private func loadRoutes() async {
        isLoading = true
        do {
            routes = try await CABSAPIService.shared.fetchAllRoutes()
            if selectedRoute == nil {
                selectedRoute = routes.first
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
    
    private func fetchBuses() async {
        guard let routeCode = selectedRoute?.id else { return }
        
        do {
            let newBuses = try await CABSAPIService.shared.fetchVehicles(routeCode: routeCode)
            
            // Start animation from current positions to new positions
            targetBuses = newBuses
            animationProgress = 0
            startAnimation()
            
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    private func startAnimation() {
        animationTimer?.invalidate()
        
        let startBuses = animatedBuses.isEmpty ? targetBuses : animatedBuses
        let frameInterval: TimeInterval = 1.0 / 60.0 // 60 FPS
        let totalFrames = animationDuration / frameInterval
        var currentFrame: Double = 0
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            currentFrame += 1
            let progress = min(currentFrame / totalFrames, 1.0)
            
            // Ease-out interpolation
            let easedProgress = 1 - pow(1 - progress, 3)
            
            Task { @MainActor in
                self.animatedBuses = self.interpolateBuses(from: startBuses, to: self.targetBuses, progress: easedProgress)
                
                if progress >= 1.0 {
                    timer.invalidate()
                    self.buses = self.targetBuses
                    self.animatedBuses = self.targetBuses
                }
            }
        }
    }
    
    private func interpolateBuses(from: [Bus], to: [Bus], progress: Double) -> [Bus] {
        return to.map { targetBus in
            if let sourceBus = from.first(where: { $0.id == targetBus.id }) {
                return sourceBus.interpolated(to: targetBus, progress: progress)
            }
            return targetBus
        }
    }
}

// MARK: - Map Region

extension BusTrackingViewModel {
    /// OSU campus center coordinates
    static let osuCenter = CLLocationCoordinate2D(latitude: 40.0067, longitude: -83.0305)
    
    /// Default map span for campus view
    static let defaultSpan = 0.02
}
