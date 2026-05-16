//
//  ContentView.swift
//  CABSFlight
//
//  Created by Steve on 2/7/26.
//

import SwiftUI
import MapKit

/// Main entry point that switches between Classic and Liquid Glass UI based on iOS version
struct ContentView: View {
    @State private var viewModel = BusViewModel()
    @State private var preferences = UserPreferences()
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasSeenOnboarding")

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                LiquidGlassView()
                    .environment(viewModel)
            } else {
                ClassicFlightyView()
                    .environment(viewModel)
            }
        }
        .onAppear {
            viewModel.userPreferences = preferences
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(viewModel: viewModel, preferences: preferences)
                .interactiveDismissDisabled()
        }
    }
}

// MARK: - Shared Components

/// Wrapper for polyline coordinates to use in ForEach
struct IdentifiablePolyline: Identifiable {
    let id: String
    let coordinates: [CLLocationCoordinate2D]
}

extension Route {
    func routeLockedMapRect() -> MKMapRect {
        var rect = MKMapRect.null

        for coordinate in routeFramingCoordinates where coordinate.isValidMapCoordinate {
            let point = MKMapPoint(coordinate)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 1, height: 1)
            rect = rect.isNull ? pointRect : rect.union(pointRect)
        }

        guard !rect.isNull else {
            return Self.defaultCampusMapRect()
        }

        let centerLatitude = MKMapPoint(x: rect.midX, y: rect.midY).coordinate.latitude
        let mapPointsPerMeter = MKMapPointsPerMeterAtLatitude(centerLatitude)
        let minimumDimension = 700 * mapPointsPerMeter

        if rect.width < minimumDimension {
            rect = rect.insetBy(dx: -(minimumDimension - rect.width) / 2, dy: 0)
        }

        if rect.height < minimumDimension {
            rect = rect.insetBy(dx: 0, dy: -(minimumDimension - rect.height) / 2)
        }

        let horizontalPadding = max(rect.width * 0.18, 180 * mapPointsPerMeter)
        let verticalPadding = max(rect.height * 0.18, 180 * mapPointsPerMeter)
        return rect.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
    }

    private var routeFramingCoordinates: [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []

        for pattern in patterns {
            coordinates.append(contentsOf: PolylineDecoder.decode(pattern.encodedPolyline))
        }

        coordinates.append(contentsOf: stops.map(\.coordinate))
        return coordinates
    }

    private static func defaultCampusMapRect() -> MKMapRect {
        let center = MKMapPoint(BusViewModel.osuCenter)
        let mapPointsPerMeter = MKMapPointsPerMeterAtLatitude(BusViewModel.osuCenter.latitude)
        let halfSize = 1_200 * mapPointsPerMeter
        return MKMapRect(
            x: center.x - halfSize,
            y: center.y - halfSize,
            width: halfSize * 2,
            height: halfSize * 2
        )
    }
}

private extension CLLocationCoordinate2D {
    var isValidMapCoordinate: Bool {
        CLLocationCoordinate2DIsValid(self)
            && latitude.isFinite
            && longitude.isFinite
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
