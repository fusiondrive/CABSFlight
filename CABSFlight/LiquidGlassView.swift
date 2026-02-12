//
//  LiquidGlassView.swift
//  CABSFlight
//
//  iOS 26+ "Liquid Glass" design with glossy materials and glowing effects
//

import SwiftUI
import MapKit

/// Liquid Glass UI for iOS 26+ with glossy materials and 3D effects
@available(iOS 26, *)
struct LiquidGlassView: View {
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
            // MARK: - Map (Full Screen)
            // Extracted to separate struct to reduce compiler complexity
            LiquidMapLayer(viewModel: viewModel, cameraPosition: $cameraPosition)
            
            // MARK: - Header Overlay (Top)
            VStack {
                LiquidHeaderOverlay(viewModel: viewModel)
                Spacer()
            }
            
            // MARK: - Bottom Overlays (Floating)
            VStack(spacing: 0) {
                Spacer()
                
                // Route buttons (above card)
                LiquidBottomOverlay(viewModel: viewModel)
                    .zIndex(10)
                
                // Info card (floating at bottom)
                if shouldShowInfoCard {
                    LiquidInfoCard(viewModel: viewModel, onFocusBus: zoomToBus)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity)
                                    .animation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0)),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                                    .animation(.easeOut(duration: 0.2))
                            )
                        )
                }
            }
            // Dynamic bottom padding: lift buttons when no card, tight when card shown
            .padding(.bottom, shouldShowInfoCard ? 8 : 50)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: shouldShowInfoCard)
            .ignoresSafeArea(.container, edges: .bottom) // Measure from physical screen edge
        }
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

// MARK: - Liquid Map Layer

@available(iOS 26, *)
struct LiquidMapLayer: View {
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
        .safeAreaPadding(.bottom, 100) // Push Apple Maps logo above buttons
        .ignoresSafeArea() // Map fills entire screen
        .onTapGesture {
            viewModel.selectedStop = nil
            viewModel.selectedVehicle = nil
        }
        .onChange(of: viewModel.selectedRoute?.id) { _, _ in
            if let route = viewModel.selectedRoute {
                viewModel.selectedStop = nil
                viewModel.selectedVehicle = nil
                let region = calculateBoundingRegion(for: route)
                withAnimation(.easeInOut(duration: 0.5)) {
                    cameraPosition = .region(region)
                }
            }
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
                LiquidStationView(
                    routeColor: viewModel.selectedRoute?.officialColor ?? .red,
                    isSelected: viewModel.selectedStop?.id == stop.id
                )
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectStop(stop)
                }
                .zIndex(1)
            }
        }
    }

    @MapContentBuilder
    private var busLayer: some MapContent {
        ForEach(viewModel.animatedBuses) { bus in
            Annotation("", coordinate: bus.coordinate) {
                LiquidBusMarker(
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
                .zIndex(100)
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

    private func calculateBoundingRegion(for route: Route) -> MKCoordinateRegion {
        var coords: [CLLocationCoordinate2D] = []
        for pattern in route.patterns {
            coords.append(contentsOf: PolylineDecoder.decode(pattern.encodedPolyline))
        }
        coords.append(contentsOf: route.stops.map { $0.coordinate })

        guard !coords.isEmpty else {
            return MKCoordinateRegion(
                center: BusViewModel.osuCenter,
                span: MKCoordinateSpan(
                    latitudeDelta: BusViewModel.defaultSpan,
                    longitudeDelta: BusViewModel.defaultSpan
                )
            )
        }

        let lats = coords.map { $0.latitude }
        let lngs = coords.map { $0.longitude }
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.4, 0.005),
            longitudeDelta: max((lngs.max()! - lngs.min()!) * 1.4, 0.005)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

// MARK: - Liquid Glass Components

@available(iOS 26, *)
struct LiquidStationView: View {
    let routeColor: Color
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 12, height: 12)
            Circle()
                .stroke(routeColor, lineWidth: 2.5)
                .frame(width: 12, height: 12)
            // Glossy highlight
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.6), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 6, height: 6)
                .offset(x: -2, y: -2)
        }
        .scaleEffect(isSelected ? 1.14 : 1.0)
        .animation(.easeOut(duration: 0.2), value: isSelected)
        .shadow(color: routeColor.opacity(0.4), radius: 4, y: 2)
    }
}

@available(iOS 26, *)
struct LiquidBusMarker: View {
    let bus: Bus
    let routeColor: Color

    var body: some View {
        ZStack {
            // Base circle with route color
            Circle()
                .fill(routeColor)
                .frame(width: 22, height: 22)

            // Glossy overlay
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.5), .clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .frame(width: 22, height: 22)

            // White border with glow
            Circle()
                .strokeBorder(.white, lineWidth: 2)
                .frame(width: 22, height: 22)

            // Navigation arrow
            Image(systemName: "location.north.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .rotationEffect(.degrees(bus.heading == 0 ? 45 : bus.heading))
                .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
        }
        .shadow(color: routeColor.opacity(0.5), radius: 6, y: 3)
    }
}

@available(iOS 26, *)
struct LiquidInfoCard: View {
    @Bindable var viewModel: BusViewModel
    var onFocusBus: ((Bus) -> Void)?
    
    private var selectedVehicle: Bus? { viewModel.selectedVehicle }
    private var selectedStop: Stop? { viewModel.selectedStop }
    private var selectedRoute: Route? { viewModel.selectedRoute }
    private var approachingVehicles: [Bus] {
        guard let selectedStop else { return [] }
        return viewModel.vehicles.filter { $0.nextStopID == selectedStop.id }
    }
    private var statusTitle: String {
        if selectedVehicle != nil { return "VEHICLE" }
        if selectedStop != nil { return "STATION" }
        return "ROUTE"
    }
    
    /// Dynamic corner radius based on device
    private var cornerRadius: CGFloat { ScreenCornerRadius.current }
    
    /// Route color for glow effect
    private var routeColor: Color { viewModel.selectedRoute?.officialColor ?? .blue }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack {
                Text(statusTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(1)
                Spacer()
                if !viewModel.vehicles.isEmpty {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text("LIVE").font(.system(size: 10, weight: .bold)).foregroundColor(.green)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.green.opacity(0.15), in: Capsule())
                }
            }
            
            // CRITICAL FIX: Group + .id forces SwiftUI to swap views instantly
            // instead of interpolating between them (which causes text overlap/twitching)
            Group {
                if let bus = selectedVehicle {
                    // Vehicle mode
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(routeColor)
                            Text(bus.destination ?? "En Route")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.primary)
                        }
                        HStack(spacing: 12) {
                            Label("\(bus.speed) mph", systemImage: "speedometer")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
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
                                .foregroundColor(.primary.opacity(0.8))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if let stop = selectedStop {
                    // Station mode with multi-route predictions
                    let preds = viewModel.predictions(for: stop)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(stop.name)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.primary)
                        Text("Approaching Buses")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                        if preds.isEmpty {
                            Text("No buses approaching.")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(preds.prefix(5)) { pred in
                                HStack(spacing: 8) {
                                    // Route badge capsule
                                    Text(pred.route.id)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(pred.route.officialColor, in: Capsule())

                                    // Bus identifier
                                    Text("Bus \(pred.bus.id)")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.primary)

                                    Spacer()

                                    // ETA from advanced prediction algorithm
                                    Text(pred.timeDisplay)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(pred.timeDisplay == "Arriving" ? .green : .secondary)
                                }
                            }
                        }
                    }
                } else if let route = selectedRoute {
                    // Route mode
                    VStack(alignment: .leading, spacing: 6) {
                        Text(route.name)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.primary)
                        Text("\(viewModel.vehicles.count) buses currently active")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("Tap a bus or station for details.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .id(statusTitle + (selectedVehicle?.id ?? "") + (selectedStop?.id ?? ""))
            .transition(.opacity.animation(.easeInOut(duration: 0.15)))
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 44) // Home indicator (34pt) + buffer (10pt)
        // Native iOS 26 Liquid Glass effect
        .glassEffect(
            .regular.tint(routeColor.opacity(0.1)),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .shadow(color: .black.opacity(0.15), radius: 15, y: 8)
        .ignoresSafeArea(edges: .bottom) // Glass touches bottom
        .padding(.horizontal, 8) // Tighter side margins
        .padding(.bottom, 8) // Sink card close to bezel (8pt gap)
    }
}

@available(iOS 26, *)
struct LiquidHeaderOverlay: View {
    @Bindable var viewModel: BusViewModel
    @State private var showSettings = false

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CABS").font(.system(size: 34, weight: .bold)).foregroundColor(.primary)
                if let route = viewModel.selectedRoute {
                    Text(route.name).font(.system(size: 14, weight: .medium)).foregroundColor(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 12) {
                if !viewModel.animatedBuses.isEmpty {
                    LiquidLiveBadge()
                }
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                        .frame(width: 40, height: 40)
                        .glassEffect(.regular.interactive(true), in: Circle())
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 8)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom)
                )
                .frame(height: 120)
                .ignoresSafeArea()
        )
        .sheet(isPresented: $showSettings) {
            if let prefs = viewModel.userPreferences {
                SettingsView(viewModel: viewModel, preferences: prefs)
            }
        }
    }
}

@available(iOS 26, *)
struct LiquidLiveBadge: View {
    @State private var isPulsing = false
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(.green).frame(width: 8, height: 8)
                .scaleEffect(isPulsing ? 1.3 : 1.0).opacity(isPulsing ? 0.6 : 1.0)
            Text("LIVE").font(.system(size: 13, weight: .semibold)).foregroundColor(.primary.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .glassEffect(.regular.interactive(true), in: Capsule())
        .shadow(color: .green.opacity(0.15), radius: 5, y: 2)
        .onAppear { withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { isPulsing = true } }
    }
}

@available(iOS 26, *)
struct LiquidBottomOverlay: View {
    @Bindable var viewModel: BusViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.animatedBuses.isEmpty {
                HStack {
                    Image(systemName: "bus.fill").foregroundColor(.secondary)
                    Text("\(viewModel.animatedBuses.count) buses active")
                        .font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
                }.padding(.bottom, 12)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer {
                    HStack(spacing: 10) {
                        ForEach(viewModel.routes) { route in
                            LiquidRouteChip(route: route, isSelected: viewModel.selectedRoute?.id == route.id) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                    if viewModel.selectedRoute?.id == route.id {
                                        viewModel.deselectRoute()
                                    } else {
                                        viewModel.selectRoute(route)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 30) // Expand height for glow headroom
            }
            .padding(.vertical, -18) // Pull back visually
        }
        // No background - buttons float freely on map
    }
}

@available(iOS 26, *)
struct LiquidRouteChip: View {
    let route: Route
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // Dot: White when selected (pops against colored glass), Colored when unselected
                Circle()
                    .fill(isSelected ? .white : route.officialColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: isSelected ? .black.opacity(0.2) : .clear, radius: 2, y: 1)

                // Text: White when selected, Secondary when unselected
                Text(route.id)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .contentShape(Capsule())
            // Stained glass effect: tinted when selected, plain when not
            .glassEffect(
                isSelected ? .regular.tint(route.officialColor).interactive(true) : .regular.interactive(true),
                in: Capsule()
            )
            // Colored glow when selected (light passing through the gemstone)
            .shadow(
                color: isSelected ? route.officialColor.opacity(0.5) : .black.opacity(0.05),
                radius: isSelected ? 10 : 4,
                y: isSelected ? 5 : 2
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
    }
}
