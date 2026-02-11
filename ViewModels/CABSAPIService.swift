//
//  CABSAPIService.swift
//  CABSFlight
//
//  Created by Steve on 2/7/26.
//

import Foundation

/// Network service for OSU CABS API
actor CABSAPIService {
    static let shared = CABSAPIService()
    
    private let baseURL = "https://content.osu.edu/v2/bus/routes"
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()
    
    private init() {}
    
    // MARK: - Fetch All Routes
    
    /// Fetch list of all available routes
    func fetchAllRoutes() async throws -> [Route] {
        let url = URL(string: baseURL)!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try decoder.decode(CABSRoutesListResponse.self, from: data)
        
        guard let routesData = response.data?.routes else {
            return []
        }
        
        return routesData.map { Route.from(info: $0) }
    }
    
    // MARK: - Fetch Route Details
    
    /// Fetch route details including stops and patterns
    func fetchRouteDetails(code: String) async throws -> Route {
        let url = URL(string: "\(baseURL)/\(code)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try decoder.decode(CABSRouteResponse.self, from: data)
        
        let stops = (response.data?.stops ?? []).compactMap { stopData -> Stop? in
            guard let id = stopData.id,
                  let name = stopData.name,
                  let lat = stopData.latitude,
                  let lng = stopData.longitude else { return nil }
            return Stop(id: id, name: name, latitude: lat, longitude: lng)
        }
        
        let patterns = (response.data?.patterns ?? []).compactMap { patternData -> RoutePattern? in
            guard let id = patternData.id,
                  let direction = patternData.direction,
                  let polyline = patternData.encodedPolyline,
                  let length = patternData.length else { return nil }
            return RoutePattern(id: id, direction: direction, encodedPolyline: polyline, length: length)
        }
        
        // We need to get the route info for color/name
        let routes = try await fetchAllRoutes()
        let routeInfo = routes.first { $0.id == code }
        
        return Route(
            id: code,
            name: routeInfo?.name ?? code,
            colorHex: routeInfo?.colorHex ?? "#007AFF",
            stops: stops,
            patterns: patterns
        )
    }
    
    // MARK: - Fetch Vehicles
    
    /// Fetch live vehicle positions for a route
    func fetchVehicles(routeCode: String) async throws -> [Bus] {
        let url = URL(string: "\(baseURL)/\(routeCode)/vehicles")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try decoder.decode(CABSVehiclesResponse.self, from: data)
        
        guard let vehiclesData = response.data?.vehicles else {
            return []
        }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return vehiclesData.compactMap { vehicle -> Bus? in
            guard let id = vehicle.id,
                  let lat = vehicle.latitude,
                  let lng = vehicle.longitude else { return nil }
            
            let lastUpdated = vehicle.updated.flatMap { dateFormatter.date(from: $0) }
            
            return Bus(
                id: id,
                routeCode: routeCode,
                latitude: lat,
                longitude: lng,
                heading: Double(vehicle.heading ?? 0),
                speed: vehicle.speed ?? 0,
                destination: vehicle.destination,
                delayed: vehicle.delayed ?? false,
                patternId: vehicle.patternId,
                nextStopID: vehicle.nextStopID ?? vehicle.nextStopId,
                distance: vehicle.distance,
                lastUpdated: lastUpdated
            )
        }
    }
}

enum CABSError: Error, LocalizedError {
    case invalidResponse
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from CABS API"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
