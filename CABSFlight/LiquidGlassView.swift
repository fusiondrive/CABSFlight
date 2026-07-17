//
//  LiquidGlassView.swift
//  CABSFlight
//
//  iOS 26+ Liquid Glass UI with glossy materials and 3D effects.
//

import SwiftUI
import MapKit

/// Root view for the iOS 26+ Liquid Glass experience.
/// Composes the full-screen map, header overlay, floating route buttons,
/// bus/route info card, and the stop bottom sheet.
@available(iOS 26, *)
struct LiquidGlassView: View {
    @Environment(BusViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            // Map fills the entire screen; extracted to a separate struct to
            // reduce SwiftUI compiler complexity on this view's body.
            LiquidMapLayer(viewModel: viewModel, cameraPosition: $cameraPosition)

            // Header overlay (top)
            VStack {
                LiquidHeaderOverlay(viewModel: viewModel)
                Spacer()
            }

            // Bottom overlays — route strip and floating info card
            VStack(spacing: 0) {
                Spacer()

                LiquidBottomOverlay(viewModel: viewModel)
                    .zIndex(10)

                if shouldShowInfoCard {
                    LiquidInfoCard(viewModel: viewModel, onFocusBus: zoomToBus)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity)
                                    .animation(Theme.Anim.infoCardInsertion),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                                    .animation(Theme.Anim.selectionFeedback)
                            )
                        )
                }
            }
            .padding(.bottom, shouldShowInfoCard ? 0 : Theme.UI.floatingButtonsBottomPadding)
            .animation(Theme.Anim.bottomOverlay, value: shouldShowInfoCard)
            .ignoresSafeArea(.container, edges: .bottom)

            // Stop bottom sheet — lives at zIndex 30 to overlay the route buttons
            // whenever the user has a stop selected.
            //
            // Single animation owner: this `.transition` defines *how* the sheet
            // enters/leaves; the *timing* comes solely from the transaction at
            // the mutation site (sheetPresent on open, sheetDismiss on discrete
            // close, sheetRelease on interactive drag). There is deliberately no
            // container-level `.animation(value:)` here — one used to override
            // every call-site transaction, which is exactly the conflict this
            // phase removes. Reduce Motion drops the spatial move for a fade.
            if viewModel.selectedStop != nil {
                CABSBottomSheetView(viewModel: viewModel)
                    .transition(sheetTransition)
                    .zIndex(30)
            }
        }
        .onAppear {
            viewModel.startTracking()
        }
        .onDisappear {
            viewModel.stopTracking()
        }
    }

    /// Enter/exit transition for the stop sheet. Reduce Motion swaps the
    /// upward slide for a plain opacity crossfade (no vestibular motion).
    private var sheetTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .bottom).combined(with: .opacity)
    }

    // MARK: - Helpers

    private func zoomToBus(_ bus: Bus) {
        // Focusing a bus swaps the info-card content; use the info-card owner.
        withAnimation(Theme.Anim.bottomOverlay) {
            viewModel.selectBus(bus)
        }
        let region = MKCoordinateRegion(
            center: bus.coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: Theme.Map.zoomToBusSpan,
                longitudeDelta: Theme.Map.zoomToBusSpan
            )
        )
        withAnimation(Theme.Anim.cameraFly) {
            cameraPosition = .region(region)
        }
    }

    private var shouldShowInfoCard: Bool {
        // The stop sheet handles the selected-stop case; show the info card only
        // for route/vehicle modes so the two surfaces don't overlap.
        viewModel.selectedRoute != nil && viewModel.selectedStop == nil
    }
}

// MARK: - Liquid Map Layer

/// Full-screen map layer managing route polylines, stop annotations, and bus markers.
@available(iOS 26, *)
struct LiquidMapLayer: View {
    @Bindable var viewModel: BusViewModel
    @Binding var cameraPosition: MapCameraPosition


    /// Campus-wide overview used on initial load and after a stop is dismissed.
    /// Mirrors the `cameraPosition` initial value in `LiquidGlassView` so both
    /// always restore to the same framing.
    private let campusOverview: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: BusViewModel.osuCenter,
            span: MKCoordinateSpan(
                latitudeDelta: BusViewModel.defaultSpan,
                longitudeDelta: BusViewModel.defaultSpan
            )
        )
    )

    var body: some View {
        Map(position: $cameraPosition) {
            polylineLayer
            stopLayer
            busLayer
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        // Static padding keeps the map frame constant at runtime. Dynamic padding
        // (e.g. sized to sheet height) causes a layout recalculation that triggers
        // the iOS 17+ MapKit camera teleport bug on every sheet presentation.
        .safeAreaPadding(.bottom, Theme.Map.bottomPadding)
        .ignoresSafeArea()
        .onTapGesture {
            // Discrete dismissal — single owner is sheetDismiss (drives the
            // removal transition). selectedVehicle clears in the same
            // transaction; the info card has its own scoped animation owner.
            withAnimation(Theme.Anim.sheetDismiss) {
                viewModel.selectedStop = nil
                viewModel.selectedVehicle = nil
            }
        }
        .onAppear {
            lockCameraToSelectedRoute(animated: false, clearSelection: false)
        }
        .onChange(of: routeCameraKey) { _, _ in
            lockCameraToSelectedRoute()
        }
        // Because the map frame is static, camera mutations and state mutations
        // fire on the same render pass with no delay or teleport risk.
        .onChange(of: viewModel.selectedStop) { _, newStop in
            guard newStop == nil else { return }
            if viewModel.selectedRoute != nil {
                lockCameraToSelectedRoute(animated: true, clearSelection: false)
            } else {
                withAnimation(Theme.Anim.cameraFly) {
                    cameraPosition = campusOverview
                }
            }
        }
    }

    // MARK: - Map Content

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
                .frame(width: Theme.UI.stopAnnotationFrame, height: Theme.UI.stopAnnotationFrame)
                .contentShape(Circle())
                .mapItemPressEffect(isSelected: viewModel.selectedStop?.id == stop.id) {
                    // Offset the camera center upward so the pin sits in the visible
                    // upper ~60% of the screen above the bottom sheet.
                    // Uses mathematical coordinate offsetting instead of dynamic safe
                    // area padding to prevent iOS 17+ MapKit render race conditions.
                    let span = Theme.Map.closeUpSpan
                    let offsetLat = stop.coordinate.latitude - (span * Theme.Map.closeUpVerticalOffsetFraction)
                    let targetCenter = CLLocationCoordinate2D(
                        latitude: offsetLat,
                        longitude: stop.coordinate.longitude
                    )
                    // Single owner for presentation.
                    withAnimation(Theme.Anim.sheetPresent) {
                        viewModel.selectStop(stop)
                    }
                    withAnimation(Theme.Anim.stopCameraFly) {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: targetCenter,
                            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
                        ))
                    }
                }
                .zIndex(viewModel.selectedStop?.id == stop.id ? 10 : 1)
            }
        }
    }

    @MapContentBuilder
    private var busLayer: some MapContent {
        // Reads the presentation layer (`displayedBuses`); coordinate and
        // heading changes animate natively via the transaction applied in
        // `BusViewModel.applyVehicleUpdate`.
        ForEach(viewModel.displayedBuses) { displayed in
            Annotation("", coordinate: displayed.coordinate) {
                LiquidBusMarker(
                    displayed: displayed,
                    routeColor: viewModel.selectedRoute?.officialColor ?? .red
                )
                .frame(width: Theme.UI.busAnnotationFrame, height: Theme.UI.busAnnotationFrame)
                .contentShape(Rectangle())
                .mapItemPressEffect(isSelected: viewModel.selectedVehicle?.id == displayed.id) {
                    if viewModel.selectedVehicle?.id == displayed.id {
                        viewModel.selectedVehicle = nil
                    } else {
                        viewModel.selectBus(displayed.bus)
                    }
                }
                .zIndex(100)
            }
        }
    }

    // MARK: - Derived Data

    private var routePolylines: [IdentifiablePolyline] {
        guard let route = viewModel.selectedRoute else { return [] }
        return route.patterns.enumerated().map { index, pattern in
            IdentifiablePolyline(
                id: "\(route.id)-\(index)",
                coordinates: PolylineDecoder.decode(pattern.encodedPolyline)
            )
        }
    }

    private var routeStops: [Stop] {
        viewModel.selectedRoute?.stops ?? []
    }

    /// A stable string key that changes whenever the selected route's content
    /// changes shape — used to trigger camera re-framing on route data updates.
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

    // MARK: - Camera Control

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
            withAnimation(Theme.Anim.cameraFly) {
                cameraPosition = .rect(mapRect)
            }
        } else {
            cameraPosition = .rect(mapRect)
        }
    }
}

// MARK: - Liquid Glass Components

/// Stop annotation marker rendered at each station along the route polyline.
@available(iOS 26, *)
struct LiquidStationView: View {
    let routeColor: Color
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: Theme.UI.stopMarkerSize, height: Theme.UI.stopMarkerSize)
            Circle()
                .stroke(routeColor, lineWidth: Theme.UI.stopMarkerStrokeWidth)
                .frame(width: Theme.UI.stopMarkerSize, height: Theme.UI.stopMarkerSize)
            // Glossy specular highlight
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
        .animation(Theme.Anim.selectionFeedback, value: isSelected)
        .shadow(color: routeColor.opacity(0.4), radius: 4, y: 2)
    }
}

/// Bus vehicle annotation marker displaying route color and heading direction.
@available(iOS 26, *)
struct LiquidBusMarker: View {
    let displayed: DisplayedBus
    let routeColor: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(routeColor)
                .frame(width: Theme.UI.busMarkerSize, height: Theme.UI.busMarkerSize)

            // Glossy overlay
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.5), .clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .frame(width: Theme.UI.busMarkerSize, height: Theme.UI.busMarkerSize)

            Circle()
                .strokeBorder(.white, lineWidth: 2)
                .frame(width: Theme.UI.busMarkerSize, height: Theme.UI.busMarkerSize)

            if let heading = displayed.continuousHeading {
                // Continuous unwrapped angle — 350°→10° rotates +20°, never the
                // long way around.
                Image(systemName: "location.north.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(heading))
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            } else {
                // No valid heading from the data source: a direction-free dot
                // instead of a fabricated arrow.
                Circle()
                    .fill(.white)
                    .frame(width: 7, height: 7)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            }
        }
        .shadow(color: routeColor.opacity(0.5), radius: 6, y: 3)
    }
}

// MARK: - Liquid Bottom Card Shell

/// Single source of truth for the glass card shell appearance.
///
/// Both `LiquidInfoCard` and `CABSBottomSheetView` use this as their outer
/// container. All layout, glass material, shadow, and safe-area modifiers
/// live here so both surfaces are pixel-perfect matches.
@available(iOS 26, *)
struct LiquidBottomCardShell<Content: View>: View {
    let tintColor: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.bottom, Theme.UI.sheetBottomInset)
        .glassEffect(
            .regular.tint(tintColor.opacity(Theme.UI.glassShellTintOpacity)),
            in: RoundedRectangle(cornerRadius: Theme.UI.sheetCornerRadius, style: .continuous)
        )
        .shadow(color: .black.opacity(0.15), radius: 15, y: 8)
        .ignoresSafeArea(edges: .bottom)
        .padding(.horizontal, Theme.UI.sheetHorizontalPadding)
        .padding(.bottom, Theme.UI.sheetBottomPadding)
    }
}

// MARK: - Liquid Info Card

/// Floating card shown when a route or vehicle is selected.
/// Hidden while the stop sheet is active to prevent overlap.
@available(iOS 26, *)
struct LiquidInfoCard: View {
    @Bindable var viewModel: BusViewModel
    var onFocusBus: ((Bus) -> Void)?

    private var selectedVehicle: Bus?   { viewModel.selectedVehicle }
    private var selectedStop:    Stop?  { viewModel.selectedStop }
    private var selectedRoute:   Route? { viewModel.selectedRoute }

    private var statusTitle: String {
        if selectedVehicle != nil { return "VEHICLE" }
        if selectedStop    != nil { return "STATION" }
        return "ROUTE"
    }

    private var routeColor: Color { viewModel.selectedRoute?.officialColor ?? .blue }

    var body: some View {
        LiquidBottomCardShell(tintColor: routeColor) {
            VStack(alignment: .leading, spacing: 8) {
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

                // `Group + .id` forces SwiftUI to replace the view tree rather than
                // cross-fade between states, preventing text overlap during transitions.
                Group {
                    if let bus = selectedVehicle {
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
                                Label("\(viewModel.estimatedSpeedMPH(for: bus)) mph", systemImage: "speedometer")
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
                                        Text(pred.route.id)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(pred.route.officialColor, in: Capsule())
                                        Text("Bus \(pred.bus.id)")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Text(pred.timeDisplay)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(pred.timeDisplay == "Due" ? .green : .secondary)
                                    }
                                }
                            }
                        }
                    } else if let route = selectedRoute {
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
                .transition(.opacity.animation(Theme.Anim.infoCardFade))
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
        }
    }
}

// MARK: - Liquid Header Overlay

/// Top-of-screen overlay containing the app title, selected route name,
/// LIVE badge, and settings button.
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
                if !viewModel.latestBuses.isEmpty {
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

// MARK: - Liquid Live Badge

/// Animated "LIVE" pill shown in the header when real-time bus data is available.
@available(iOS 26, *)
struct LiquidLiveBadge: View {
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(.green).frame(width: 8, height: 8)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0.6 : 1.0)
            Text("LIVE").font(.system(size: 13, weight: .semibold)).foregroundColor(.primary.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .glassEffect(.regular.interactive(true), in: Capsule())
        .shadow(color: .green.opacity(0.15), radius: 5, y: 2)
        .onAppear {
            withAnimation(Theme.Anim.liveBadgePulse) { isPulsing = true }
        }
    }
}

// MARK: - Liquid Bottom Overlay

/// Floating route selection strip and active-bus count indicator.
@available(iOS 26, *)
struct LiquidBottomOverlay: View {
    @Bindable var viewModel: BusViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Business-facing count reads latest data, not presentation state.
            if !viewModel.latestBuses.isEmpty {
                HStack {
                    Image(systemName: "bus.fill").foregroundColor(.secondary)
                    Text("\(viewModel.latestBuses.count) buses active")
                        .font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
                }.padding(.bottom, 12)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer {
                    HStack(spacing: 10) {
                        ForEach(viewModel.routes) { route in
                            LiquidRouteChip(route: route, isSelected: viewModel.selectedRoute?.id == route.id) {
                                withAnimation(Theme.Anim.routeChip) {
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
                .padding(.vertical, 30) // Expands intrinsic height for glow shadow headroom
            }
            .padding(.vertical, -18) // Negative padding resets visual size; extra height is headroom only
        }
        // No background — chips float freely above the map
    }
}

// MARK: - Liquid Route Chip

/// Selectable pill for a single transit route in the horizontal route strip.
@available(iOS 26, *)
struct LiquidRouteChip: View {
    let route: Route
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // Active chips use white to pop against the colored glass tint.
                Circle()
                    .fill(isSelected ? .white : route.officialColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: isSelected ? .black.opacity(0.2) : .clear, radius: 2, y: 1)

                Text(route.id)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .contentShape(Capsule())
            .glassEffect(
                isSelected ? .regular.tint(route.officialColor).interactive(true) : .regular.interactive(true),
                in: Capsule()
            )
            // Colored glow when selected, simulating light passing through stained glass.
            .shadow(
                color: isSelected ? route.officialColor.opacity(0.5) : .black.opacity(0.05),
                radius: isSelected ? 10 : 4,
                y: isSelected ? 5 : 2
            )
        }
        .buttonStyle(.plain)
        .animation(Theme.Anim.routeChip, value: isSelected)
    }
}
