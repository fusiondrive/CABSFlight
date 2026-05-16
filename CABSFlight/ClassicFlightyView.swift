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
            ClassicMapLayer(viewModel: viewModel, cameraPosition: $cameraPosition)
            
            // MARK: - Overlay UI
            VStack(spacing: 0) {
                ClassicHeaderOverlay(viewModel: viewModel)
                Spacer()
                ClassicBottomOverlay(viewModel: viewModel)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if shouldShowInfoCard {
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

    private var shouldShowInfoCard: Bool {
        viewModel.selectedRoute != nil
    }
}

// MARK: - Classic Map Layer

struct ClassicMapLayer: View {
    @Bindable var viewModel: BusViewModel
    @Binding var cameraPosition: MapCameraPosition

    var body: some View {
        Map(position: $cameraPosition) {
            polylineLayer
            stopLayer
            busLayer
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .ignoresSafeArea()
        .onTapGesture {
            viewModel.selectedStop = nil
            viewModel.selectedVehicle = nil
        }
        .onAppear {
            lockCameraToSelectedRoute(animated: false, clearSelection: false)
        }
        .onChange(of: routeCameraKey) { _, _ in
            lockCameraToSelectedRoute()
        }
    }

    @MapContentBuilder
    private var polylineLayer: some MapContent {
        ForEach(routePolylines) { polyline in
            MapPolyline(coordinates: polyline.coordinates)
                .stroke(
                    viewModel.selectedRoute?.officialColor ?? .red,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                )
        }
    }

    @MapContentBuilder
    private var stopLayer: some MapContent {
        ForEach(routeStops) { stop in
            Annotation("", coordinate: stop.coordinate, anchor: .center) {
                ClassicStationView(
                    routeColor: viewModel.selectedRoute?.officialColor ?? .red,
                    isSelected: viewModel.selectedStop?.id == stop.id
                )
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectStop(stop)
                }
            }
        }
    }

    @MapContentBuilder
    private var busLayer: some MapContent {
        ForEach(viewModel.animatedBuses) { bus in
            Annotation("", coordinate: bus.coordinate) {
                ClassicBusMarker(
                    bus: bus,
                    routeColor: viewModel.selectedRoute?.officialColor ?? .red
                )
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .onTapGesture {
                    if viewModel.selectedVehicle?.id == bus.id {
                        viewModel.selectedVehicle = nil
                    } else {
                        viewModel.selectBus(bus)
                    }
                }
            }
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

    private var routeCameraKey: String {
        guard let route = viewModel.selectedRoute else { return "none" }
        return [
            route.id,
            String(route.stops.count),
            String(route.patterns.count),
            route.stops.first?.id ?? "",
            route.stops.last?.id ?? "",
            route.patterns.first?.id ?? "",
            route.patterns.last?.id ?? ""
        ].joined(separator: "-")
    }

    private func lockCameraToSelectedRoute(
        animated: Bool = true,
        clearSelection: Bool = true
    ) {
        guard let route = viewModel.selectedRoute else { return }

        if clearSelection {
            viewModel.selectedStop = nil
            viewModel.selectedVehicle = nil
        }

        let mapRect = route.routeLockedMapRect()
        if animated {
            withAnimation(.easeInOut(duration: 0.5)) {
                cameraPosition = .rect(mapRect)
            }
        } else {
            cameraPosition = .rect(mapRect)
        }
    }
}

// MARK: - Classic Components

struct ClassicStationView: View {
    let routeColor: Color
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(routeColor, lineWidth: 2.5))
            .scaleEffect(isSelected ? 1.14 : 1.0)
            .animation(.easeOut(duration: 0.2), value: isSelected)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}

struct ClassicBusMarker: View {
    let bus: Bus
    let routeColor: Color

    var body: some View {
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
}

struct ClassicInfoCard: View {
    @Bindable var viewModel: BusViewModel
    var onFocusBus: ((Bus) -> Void)?
    
    private var selectedVehicle: Bus? { viewModel.selectedVehicle }
    private var selectedStop: Stop? { viewModel.selectedStop }
    private var selectedRoute: Route? { viewModel.selectedRoute }
    private var statusTitle: String {
        if selectedVehicle != nil { return "VEHICLE" }
        if selectedStop != nil { return "STATION" }
        return "ROUTE"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(statusTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(1)
                Spacer()
                if !viewModel.vehicles.isEmpty {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text("LIVE").font(.system(size: 10, weight: .bold)).foregroundColor(.green)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.green.opacity(0.15)))
                }
            }
            
            if let bus = selectedVehicle {
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
                        Label("\(viewModel.estimatedSpeedMPH(for: bus)) mph", systemImage: "speedometer")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                        Label(
                            "Location \(bus.latitude, specifier: "%.4f"), \(bus.longitude, specifier: "%.4f")",
                            systemImage: "location"
                        )
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
            } else if let stop = selectedStop {
                let preds = viewModel.predictions(for: stop)
                VStack(alignment: .leading, spacing: 6) {
                    Text(stop.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    Text("Approaching Buses")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                    if preds.isEmpty {
                        Text("No buses approaching.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    } else {
                        ForEach(preds.prefix(5)) { pred in
                            HStack(spacing: 8) {
                                Text(pred.route.id)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(pred.route.officialColor))

                                Text("Bus \(pred.bus.id)")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)

                                Spacer()

                                Text(pred.timeDisplay)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(pred.timeDisplay == "Due" ? .green : .white.opacity(0.7))
                            }
                        }
                    }
                }
            } else if let route = selectedRoute {
                VStack(alignment: .leading, spacing: 6) {
                    Text(route.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    Text("\(viewModel.vehicles.count) buses currently active")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Text("Tap a bus or station for details.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
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
    @State private var showSettings = false

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
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
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
        .sheet(isPresented: $showSettings) {
            if let prefs = viewModel.userPreferences {
                SettingsView(viewModel: viewModel, preferences: prefs)
            }
        }
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
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                if viewModel.selectedRoute?.id == route.id {
                                    viewModel.deselectRoute()
                                } else {
                                    viewModel.selectRoute(route)
                                }
                            }
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
            .contentShape(Capsule()) // Fill empty space with tappable area
            .background(isSelected ? route.officialColor.opacity(0.25) : Color.white.opacity(0.08))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? route.officialColor : Color.white.opacity(0.15), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
    }
}
