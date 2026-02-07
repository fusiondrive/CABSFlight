//
//  PolylineDecoder.swift
//  CABSFlight
//
//  Created by Steve on 2/7/26.
//

import Foundation
import CoreLocation

/// Decodes Google's encoded polyline format to coordinates
enum PolylineDecoder {
    
    /// Decode an encoded polyline string to an array of coordinates
    static func decode(_ encodedPolyline: String) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        var index = encodedPolyline.startIndex
        var lat: Int = 0
        var lng: Int = 0
        
        while index < encodedPolyline.endIndex {
            // Decode latitude
            var shift = 0
            var result = 0
            var byte: Int
            
            repeat {
                byte = Int(encodedPolyline[index].asciiValue!) - 63
                result |= (byte & 0x1F) << shift
                shift += 5
                index = encodedPolyline.index(after: index)
            } while byte >= 0x20 && index < encodedPolyline.endIndex
            
            let deltaLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lat += deltaLat
            
            guard index < encodedPolyline.endIndex else { break }
            
            // Decode longitude
            shift = 0
            result = 0
            
            repeat {
                byte = Int(encodedPolyline[index].asciiValue!) - 63
                result |= (byte & 0x1F) << shift
                shift += 5
                index = encodedPolyline.index(after: index)
            } while byte >= 0x20 && index < encodedPolyline.endIndex
            
            let deltaLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lng += deltaLng
            
            let coordinate = CLLocationCoordinate2D(
                latitude: Double(lat) / 1e5,
                longitude: Double(lng) / 1e5
            )
            coordinates.append(coordinate)
        }
        
        return coordinates
    }
}
