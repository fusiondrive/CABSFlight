//
//  ClassicFlightyView.swift
//  CABSFlight
//
//  Classic dark-mode Flighty-inspired UI for iOS 25 and below
//

import SwiftUI
import MapKit

/// Classic Flighty-style dark mode view (stable for older iOS versions)
struct ClassicFlightyView: View {
    @Environment(BusViewModel.self) private var viewModel
    @State private var selectedStopID: String?
    
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
                // Layer 1: Route polylines
                ForEach(routePolylines) { polyline in
                    MapPolyline(coordinates: polyline.coordinates)
                        .stroke(
                            viewModel.selectedRoute?.officialColor ?? .red,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                        )
                }
                
                // Layer 2: Stop annotations
                ForEach(routeStops) { stop in
                    Annotation("", coordinate: stop.coordinate, anchor: .bottom) {
                        ClassicStationView(
                            stop: stop,
                            routeColor: viewModel.selectedRoute?.officialColor ?? .red,
                            isSelected: selectedStopID == stop.id,
                            onTap: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    selectedStopID = selectedStopID == stop.id ? nil : stop.id
                                }
                            }
                        )
                    }
                }
                
                // Layer 3: Bus annotations
                ForEach(viewModel.animatedBuses) { bus in
                    Annotation("", coordinate: bus.coordinate) {
                        ClassicBusMarker(
                            bus: bus,
                            routeColor: viewModel.selectedRoute?.officialColor ?? .red,
                            isSelected: viewModel.selectedBus?.id == bus.id
                        )
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                if viewModel.selectedBus?.id == bus.id {
                                    viewModel.clearBusSelection()
                                } else {
                                    viewModel.selectBus(bus)
                                }
                            }
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .mapControlVisibility(.hidden)
            .ignoresSafeArea()
            .onTapGesture {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    viewModel.clearBusSelection()
                    selectedStopID = nil
                }
            }
            .onChange(of: viewModel.selectedRoute?.id) { _, _ in
                if let route = viewModel.selectedRoute {
                    selectedStopID = nil
                    let region = calculateBoundingRegion(for: route)
                    withAnimation(.easeInOut(duration: 0.5)) {
                        cameraPosition = .region(region)
                    }
                }
            }
            
            // MARK: - Overlay UI
            VStack(spacing: 0) {
                ClassicHeaderOverlay(viewModel: viewModel)
                Spacer()
                ClassicBottomOverlay(viewModel: viewModel)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !viewModel.animatedBuses.isEmpty {
                ClassicInfoCard(viewModel: viewModel, onFocusBus: zoomToBus)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { viewModel.startTracking() }
        .onDisappear { viewModel.stopTracking() }
    }
    
    // MARK: - Helpers
    
    private func zoomToBus(_ bus: Bus) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            viewModel.selectBus(bus)
        }
        let region = MKCoordinateRegion(
            center: bus.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
        )
        withAnimation(.easeInOut(duration: 0.5)) {
            cameraPosition = .region(region)
        }
    }
    
    private var routePolylines: [IdentifiablePolyline] {
        guard let route = viewModel.selectedRoute else { return [] }
        return route.patterns.enumerated().map { index, pattern in
            IdentifiablePolyline(id: "\(route.id)-\(index)", coordinates: PolylineDecoder.decode(pattern.encodedPolyline))
        }
    }
    
    private var routeStops: [Stop] {
        viewModel.selectedRoute?.stops ?? []
    }
    
    private func calculateBoundingRegion(for route: Route) -> MKCoordinateRegion {
        var coords: [CLLocationCoordinate2D] = []
        for pattern in route.patterns {
            coords.append(contentsOf: PolylineDecoder.decode(pattern.encodedPolyline))
        }
        coords.append(contentsOf: route.stops.map { $0.coordinate })
        
        guard !coords.isEmpty else {
            return MKCoordinateRegion(center: BusViewModel.osuCenter, span: MKCoordinateSpan(latitudeDelta: BusViewModel.defaultSpan, longitudeDelta: BusViewModel.defaultSpan))
        }
        
        let lats = coords.map { $0.latitude }
        let lngs = coords.map { $0.longitude }
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lngs.min()! + lngs.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((lats.max()! - lats.min()!) * 1.4, 0.005), longitudeDelta: max((lngs.max()! - lngs.min()!) * 1.4, 0.005))
        return MKCoordinateRegion(center: center, span: span)
    }
}

// MARK: - Classic Components

struct ClassicStationView: View {
    let stop: Stop
    let routeColor: Color
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 4) {
            if isSelected {
                Text(stop.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white).shadow(color: .black.opacity(0.4), radius: 4, y: 2))
                    .transition(.scale.combined(with: .opacity))
            }
            Circle()
                .fill(.white)
                .frame(width: isSelected ? 16 : 12, height: isSelected ? 16 : 12)
                .overlay(Circle().stroke(routeColor, lineWidth: isSelected ? 3 : 2.5))
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        .onTapGesture { onTap() }
    }
}

struct ClassicBusMarker: View {
    let bus: Bus
    let routeColor: Color
    var isSelected: Bool = false
    
    var body: some View {
        VStack(spacing: 4) {
            if isSelected {
                Text(bus.id)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.white).shadow(color: .black.opacity(0.3), radius: 2, y: 1))
                    .transition(.scale.combined(with: .opacity))
            }
            ZStack {
                Circle().fill(routeColor).frame(width: 22, height: 22)
                Circle().strokeBorder(.white, lineWidth: 2).frame(width: 22, height: 22)
                Image(systemName: "location.north.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(bus.heading == 0 ? 45 : bus.heading))
            }
            .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
        }
        .scaleEffect(isSelected ? 1.4 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isSelected)
    }
}

struct ClassicInfoCard: View {
    @Bindable var viewModel: BusViewModel
    var onFocusBus: ((Bus) -> Void)?
    
    private var displayBus: Bus? { viewModel.selectedBus ?? viewModel.animatedBuses.first }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(viewModel.selectedRoute?.name ?? "BUS ROUTE")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(1)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("LIVE").font(.system(size: 10, weight: .bold)).foregroundColor(.green)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Color.green.opacity(0.15)))
            }
            
            if let bus = displayBus {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(viewModel.selectedRoute?.officialColor ?? .white)
                        Text(bus.destination ?? "En Route")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                    }
                    HStack(spacing: 12) {
                        Label("\(bus.speed) mph", systemImage: "speedometer")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                        if bus.delayed {
                            Label("Delayed", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.orange)
                        }
                        Spacer()
                        Button { onFocusBus?(bus) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "location.fill").font(.system(size: 10))
                                Text("Bus \(bus.id)").font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 20).fill(Color(white: 0.1).opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
    }
}

struct ClassicHeaderOverlay: View {
    @Bindable var viewModel: BusViewModel
    
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CABS").font(.system(size: 34, weight: .bold)).foregroundColor(.white)
                if let route = viewModel.selectedRoute {
                    Text(route.name).font(.system(size: 14, weight: .medium)).foregroundColor(.white.opacity(0.6))
                }
            }
            Spacer()
            if !viewModel.animatedBuses.isEmpty { ClassicLiveBadge() }
            Button { viewModel.loadMockData() } label: {
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(10)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
        }
        .padding(.horizontal, 20).padding(.top, 8)
        .background(
            LinearGradient(colors: [.black, .black.opacity(0.7), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 120).ignoresSafeArea()
        )
    }
}

struct ClassicLiveBadge: View {
    @State private var isPulsing = false
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(.green).frame(width: 8, height: 8)
                .scaleEffect(isPulsing ? 1.3 : 1.0).opacity(isPulsing ? 0.6 : 1.0)
            Text("LIVE").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.7))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.1)).overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1)))
        .onAppear { withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { isPulsing = true } }
    }
}

struct ClassicBottomOverlay: View {
    @Bindable var viewModel: BusViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.animatedBuses.isEmpty {
                HStack {
                    Image(systemName: "bus.fill").foregroundColor(.white.opacity(0.5))
                    Text("\(viewModel.animatedBuses.count) buses active")
                        .font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.7))
                }.padding(.bottom, 12)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.routes) { route in
                        ClassicRouteChip(route: route, isSelected: viewModel.selectedRoute?.id == route.id) {
                            viewModel.selectRoute(route)
                        }
                    }
                }.padding(.horizontal, 20)
            }.padding(.vertical, 12)
        }
        .background(
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.85), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
}

struct ClassicRouteChip: View {
    let route: Route
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle().fill(route.officialColor).frame(width: 10, height: 10)
                Text(route.id).font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(isSelected ? route.officialColor.opacity(0.25) : Color.white.opacity(0.08))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? route.officialColor : Color.white.opacity(0.15), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
    }
}
