//
//  APIResponse.swift
//  CABSFlight
//
//  Created by Steve on 2/7/26.
//

import Foundation

// MARK: - Routes List Response
// GET https://content.osu.edu/v2/bus/routes

struct CABSRoutesListResponse: Codable {
    let data: RoutesListData?
    let lastModified: String?
    let status: String?
    
    struct RoutesListData: Codable {
        let routes: [RouteInfo]?
    }
    
    struct RouteInfo: Codable {
        let code: String
        let color: String
        let name: String
    }
}

// MARK: - Route Details Response
// GET https://content.osu.edu/v2/bus/routes/{code}

struct CABSRouteResponse: Codable {
    let data: RouteData?
    let lastModified: String?
    let status: String?
    
    struct RouteData: Codable {
        let patterns: [PatternData]?
        let stops: [StopData]?
    }
    
    struct PatternData: Codable {
        let direction: String?
        let encodedPolyline: String?
        let id: String?
        let length: Int?
    }
    
    struct StopData: Codable {
        let id: String?
        let latitude: Double?
        let longitude: Double?
        let name: String?
    }
}

// MARK: - Vehicles Response
// GET https://content.osu.edu/v2/bus/routes/{code}/vehicles

struct CABSVehiclesResponse: Codable {
    let data: VehiclesData?
    let lastModified: String?
    let status: String?
    
    struct VehiclesData: Codable {
        let vehicles: [VehicleData]?
    }
    
    struct VehicleData: Codable {
        let id: String?
        let latitude: Double?
        let longitude: Double?
        let heading: Int?
        let speed: Int?
        let updated: String?
        let delayed: Bool?
        let destination: String?
        let distance: Int?
        let patternId: String?
        let nextStopId: String?
        let nextStopID: String?
        let routeCode: String?
    }
}
