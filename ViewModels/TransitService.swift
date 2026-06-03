//
//  TransitService.swift
//  CABSFlight
//
//  Protocol-oriented data layer for transit data.
//  Swap CABSMockService for a live implementation without touching any view or view model.
//

import Foundation

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
