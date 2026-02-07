//
//  MapContainerView.swift
//  CABSFlight
//
//  Created by Steve on 2/7/26.
//

import SwiftUI
import MapKit

/// Main map view with dark styling and bus annotations
struct MapContainerView: View {
    @ObservedObject var viewModel: BusTrackingViewModel
    
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: BusTrackingViewModel.osuCenter,
            span: MKCoordinateSpan(
                latitudeDelta: BusTrackingViewModel.defaultSpan,
                longitudeDelta: BusTrackingViewModel.defaultSpan
            )
        )
    )
    
    var body: some View {
        Map(position: $position) {
            // Bus annotations
            ForEach(viewModel.animatedBuses) { bus in
                Annotation("", coordinate: bus.coordinate) {
                    BusAnnotationView(
                        bus: bus,
                        color: viewModel.selectedRoute?.color ?? Theme.accent
                    )
                }
            }
            
            // Stop annotations
            if let route = viewModel.selectedRoute {
                ForEach(route.stops) { stop in
                    Annotation(stop.name, coordinate: stop.coordinate) {
                        StopAnnotationView()
                    }
                }
            }
        }
        .mapStyle(.standard(
            elevation: .realistic,
            pointsOfInterest: .excludingAll,
            showsTraffic: false
        ))
        .mapControlVisibility(.hidden)
        .ignoresSafeArea()
    }
}

/// Bus marker with heading indicator
struct BusAnnotationView: View {
    let bus: Bus
    let color: Color
    
    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 44, height: 44)
            
            // Main circle
            Circle()
                .fill(color)
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
            
            // Bus icon
            Image(systemName: "bus.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
            
            // Heading indicator
            HeadingIndicator(heading: bus.heading, color: color)
        }
        .shadow(color: color.opacity(0.5), radius: 8, x: 0, y: 4)
    }
}

/// Directional arrow showing bus heading
struct HeadingIndicator: View {
    let heading: Double
    let color: Color
    
    var body: some View {
        Image(systemName: "arrowtriangle.up.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .offset(y: -24)
            .rotationEffect(.degrees(heading))
    }
}

/// Stop marker
struct StopAnnotationView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.cardBackground)
                .frame(width: 12, height: 12)
            
            Circle()
                .stroke(Theme.textSecondary, lineWidth: 1.5)
                .frame(width: 12, height: 12)
        }
    }
}

#Preview {
    MapContainerView(viewModel: BusTrackingViewModel())
        .preferredColorScheme(.dark)
}
