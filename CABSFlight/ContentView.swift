//
//  ContentView.swift
//  CABSFlight
//
//  Created by Steve on 2/7/26.
//

import SwiftUI
import MapKit

/// Main app view with Flighty-inspired dark map and bus tracking
struct ContentView: View {
    @State private var viewModel = BusViewModel()
    
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: BusViewModel.osuCenter,
            span: MKCoordinateSpan(
                latitudeDelta: BusViewModel.defaultSpan,
                longitudeDelta: BusViewModel.defaultSpan
            )
        )
    )
    
    var body: some View {
        ZStack {
            // MARK: - Map
            Map(position: $cameraPosition) {
                // Route polylines
                ForEach(routePolylines, id: \.self) { coordinates in
                    MapPolyline(coordinates: coordinates)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.gray.opacity(0.3),
                                    Color.gray.opacity(0.6),
                                    Color.gray.opacity(0.3)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                        )
                }
                
                // Bus annotations
                ForEach(viewModel.animatedBuses) { bus in
                    Annotation("", coordinate: bus.coordinate) {
                        BusMarkerView(bus: bus)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .mapControlVisibility(.hidden)
            .ignoresSafeArea()
            
            // MARK: - Overlay UI
            VStack(spacing: 0) {
                // Top header
                HeaderOverlay(viewModel: viewModel)
                
                Spacer()
                
                // Bottom route picker
                BottomOverlay(viewModel: viewModel)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.startTracking()
        }
        .onDisappear {
            viewModel.stopTracking()
        }
    }
    
    // MARK: - Computed Properties
    
    /// Decoded polyline coordinates for the selected route
    private var routePolylines: [[CLLocationCoordinate2D]] {
        guard let route = viewModel.selectedRoute else { return [] }
        return route.patterns.map { pattern in
            PolylineDecoder.decode(pattern.encodedPolyline)
        }
    }
}

// MARK: - Bus Marker View

/// OSU red bus marker with heading rotation
struct BusMarkerView: View {
    let bus: Bus
    
    /// OSU Scarlet Red
    private let osuRed = Color(hex: "#BB0000")
    
    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(osuRed.opacity(0.3))
                .frame(width: 40, height: 40)
            
            // White background stroke
            Image(systemName: "location.north.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .rotationEffect(.degrees(bus.heading))
            
            // Red arrow on top
            Image(systemName: "location.north.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(osuRed)
                .rotationEffect(.degrees(bus.heading))
        }
        .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Header Overlay

struct HeaderOverlay: View {
    @Bindable var viewModel: BusViewModel
    
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CABS")
                    .font(.system(size: 34, weight: .bold, design: .default))
                    .foregroundColor(.white)
                
                if let route = viewModel.selectedRoute {
                    Text(route.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            Spacer()
            
            // Live indicator
            if !viewModel.animatedBuses.isEmpty {
                LiveBadge()
            }
            
            // Mock data button (for testing)
            Button {
                viewModel.loadMockData()
            } label: {
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(10)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .background(
            LinearGradient(
                colors: [
                    Color.black,
                    Color.black.opacity(0.7),
                    Color.black.opacity(0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            .ignoresSafeArea()
        )
    }
}

// MARK: - Live Badge

struct LiveBadge: View {
    @State private var isPulsing = false
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0.6 : 1.0)
            
            Text("LIVE")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.1))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Bottom Overlay

struct BottomOverlay: View {
    @Bindable var viewModel: BusViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Bus count info
            if !viewModel.animatedBuses.isEmpty {
                HStack {
                    Image(systemName: "bus.fill")
                        .foregroundColor(.white.opacity(0.5))
                    Text("\(viewModel.animatedBuses.count) buses active")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.bottom, 12)
            }
            
            // Route picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.routes) { route in
                        RouteChip(
                            route: route,
                            isSelected: viewModel.selectedRoute?.id == route.id,
                            action: { viewModel.selectRoute(route) }
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 12)
        }
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0),
                    Color.black.opacity(0.85),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

// MARK: - Route Chip

struct RouteChip: View {
    let route: Route
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(route.color)
                    .frame(width: 10, height: 10)
                
                Text(route.id)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? route.color.opacity(0.25) : Color.white.opacity(0.08))
                    .overlay(
                        Capsule()
                            .stroke(
                                isSelected ? route.color : Color.white.opacity(0.12),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
