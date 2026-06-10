//
//  OnboardingView.swift
//  CABSFlight
//
//  First-launch onboarding flow inspired by the iOS 26 glass onboarding pattern.
//

import SwiftUI

struct OnboardingView: View {
    var viewModel: BusViewModel
    var preferences: UserPreferences

    @Environment(\.dismiss) private var dismiss
    @State private var activePage: Int? = 0
    @State private var selectedRouteIDs: Set<String> = []

    private let pages = OnboardingPage.items
    private let pageSpring = Animation.interpolatingSpring(stiffness: 170, damping: 22)

    private var pageIndex: Int {
        min(max(activePage ?? 0, 0), pages.count - 1)
    }

    private var currentPage: OnboardingPage {
        pages[pageIndex]
    }

    var body: some View {
        ZStack {
            OnboardingAmbientBackdrop(page: currentPage)

            VStack(spacing: 0) {
                OnboardingPagerView(
                    pages: pages,
                    activePage: $activePage,
                    routes: routePreviews,
                    selectedRouteIDs: selectedRouteIDs,
                    onToggleRoute: toggleRoute
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                BottomContentView(
                    page: currentPage,
                    pageIndex: pageIndex,
                    pageCount: pages.count,
                    routeSummary: routeSummary,
                    continueTitle: pageIndex == pages.count - 1 ? "Start Exploring" : "Continue",
                    canGoBack: pageIndex > 0,
                    onBack: goBack,
                    onContinue: continueForward
                )
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .background(Color.black.ignoresSafeArea())
    }

    // MARK: - Derived Data

    private var routePreviews: [OnboardingRoutePreview] {
        if viewModel.allRoutes.isEmpty {
            return [
                .init(id: "CLS", name: "Campus Loop South", color: CABSColors.color(for: "CLS"), routeID: nil),
                .init(id: "CC", name: "Campus Connector", color: CABSColors.color(for: "CC"), routeID: nil),
                .init(id: "ER", name: "East Residential", color: CABSColors.color(for: "ER"), routeID: nil),
                .init(id: "MC", name: "Med Center", color: CABSColors.color(for: "MC"), routeID: nil)
            ]
        }

        return viewModel.allRoutes.map {
            OnboardingRoutePreview(
                id: $0.id,
                name: $0.name.capitalized,
                color: $0.officialColor,
                routeID: $0.id
            )
        }
    }

    private var routeSummary: String {
        guard pageIndex == 1 else {
            return currentPage.subtitle
        }

        if selectedRouteIDs.isEmpty {
            return "Leave it open to show every CABS route, or tap the lines you ride most."
        }

        let sorted = selectedRouteIDs.sorted().joined(separator: ", ")
        return "\(selectedRouteIDs.count) selected: \(sorted)."
    }

    // MARK: - Actions

    private func toggleRoute(_ routeID: String?) {
        guard let routeID else { return }

        withAnimation(pageSpring) {
            if selectedRouteIDs.contains(routeID) {
                selectedRouteIDs.remove(routeID)
            } else {
                selectedRouteIDs.insert(routeID)
            }
        }
    }

    private func goBack() {
        withAnimation(pageSpring) {
            activePage = max(pageIndex - 1, 0)
        }
    }

    private func continueForward() {
        withAnimation(pageSpring) {
            if pageIndex < pages.count - 1 {
                activePage = pageIndex + 1
            } else {
                finish()
            }
        }
    }

    private func finish() {
        preferences.setVisibleRoutes(selectedRouteIDs)
        preferences.completeOnboarding()
        viewModel.applyRouteFilter()
        dismiss()
    }
}

// MARK: - Data

private struct OnboardingPage: Identifiable, Hashable {
    let id: Int
    let eyebrow: String
    let title: String
    let subtitle: String
    let symbolName: String
    let tint: Color
    let glowAnchor: UnitPoint

    static let items: [OnboardingPage] = [
        .init(
            id: 0,
            eyebrow: "LIVE MAP",
            title: "CABS in Motion",
            subtitle: "Watch live buses glide across campus with a focused, glass-first map view.",
            symbolName: "bus.fill",
            tint: Theme.accent,
            glowAnchor: .center
        ),
        .init(
            id: 1,
            eyebrow: "ROUTES",
            title: "Choose Your Lines",
            subtitle: "Leave all routes visible or pick only the lines you ride most.",
            symbolName: "line.3.horizontal.decrease.circle.fill",
            tint: CABSColors.color(for: "CC"),
            glowAnchor: .top
        ),
        .init(
            id: 2,
            eyebrow: "READY",
            title: "Ready to Roll",
            subtitle: "Open the map with your route view already tuned for campus travel.",
            symbolName: "checkmark.circle.fill",
            tint: Theme.accentSecondary,
            glowAnchor: .center
        )
    ]
}

private struct OnboardingRoutePreview: Identifiable, Hashable {
    let id: String
    let name: String
    let color: Color
    let routeID: String?
}

// MARK: - Pager

private struct OnboardingPagerView: View {
    let pages: [OnboardingPage]
    @Binding var activePage: Int?
    let routes: [OnboardingRoutePreview]
    let selectedRouteIDs: Set<String>
    let onToggleRoute: (String?) -> Void

    private var pageIndex: Int {
        min(max(activePage ?? 0, 0), pages.count - 1)
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(pages) { page in
                    OnboardingPageContent(
                        page: page,
                        isActive: page.id == pageIndex,
                        routes: routes,
                        selectedRouteIDs: selectedRouteIDs,
                        onToggleRoute: onToggleRoute
                    )
                    .containerRelativeFrame(.horizontal)
                    .id(page.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollPosition(id: $activePage)
        .scrollTargetBehavior(.paging)
        .safeAreaPadding(.top, 24)
    }
}

private struct OnboardingPageContent: View {
    let page: OnboardingPage
    let isActive: Bool
    let routes: [OnboardingRoutePreview]
    let selectedRouteIDs: Set<String>
    let onToggleRoute: (String?) -> Void

    var body: some View {
        Group {
            switch page.id {
            case 0:
                AppScreenshotPage(tint: page.tint, isActive: isActive)
            case 1:
                RouteSelectionPage(
                    routes: routes,
                    selectedRouteIDs: selectedRouteIDs,
                    onToggleRoute: onToggleRoute
                )
            default:
                AllSetPage(tint: page.tint, isActive: isActive)
            }
        }
        .scaleEffect(isActive ? 1 : 0.9)
        .opacity(isActive ? 1 : 0.5)
        .animation(.interpolatingSpring(stiffness: 170, damping: 22), value: isActive)
    }
}

// MARK: - Page 1: Framed App Screenshot

private struct AppScreenshotPage: View {
    let tint: Color
    let isActive: Bool

    var body: some View {
        Image("OnboardingInApp")
            .resizable()
            .scaledToFit()
            .padding(.top, 44)
            .padding(.horizontal, 36)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .shadow(color: tint.opacity(isActive ? 0.35 : 0.12), radius: isActive ? 40 : 18, y: 24)
            .rotation3DEffect(
                .degrees(isActive ? 0 : -6),
                axis: (x: 0, y: 1, z: 0),
                perspective: 0.6
            )
    }
}

// MARK: - Page 2: Route Selection (Liquid Glass List)

private struct RouteSelectionPage: View {
    let routes: [OnboardingRoutePreview]
    let selectedRouteIDs: Set<String>
    let onToggleRoute: (String?) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)

            ForEach(routes.prefix(6)) { route in
                Button {
                    onToggleRoute(route.routeID)
                } label: {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(route.color)
                            .frame(width: 14, height: 14)
                            .shadow(color: route.color.opacity(0.55), radius: 7)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(route.id)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)

                            Text(route.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: isSelected(route) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(isSelected(route) ? route.color : .white.opacity(0.32))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 60)
                    .frame(maxWidth: .infinity)
                    .liquidOnboardingGlass(
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous),
                        tint: isSelected(route) ? route.color.opacity(0.24) : .white.opacity(0.04),
                        interactive: true
                    )
                }
                .buttonStyle(OnboardingPressButtonStyle())
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
    }

    private func isSelected(_ route: OnboardingRoutePreview) -> Bool {
        guard let routeID = route.routeID else { return selectedRouteIDs.isEmpty }
        return selectedRouteIDs.contains(routeID)
    }
}

// MARK: - Page 3: All Set

private struct AllSetPage: View {
    let tint: Color
    let isActive: Bool

    @State private var checkProgress: CGFloat = 0
    @State private var badgeScale: CGFloat = 0.4
    @State private var badgeOpacity: Double = 0
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                // Expanding pulse rings
                ForEach(0..<2, id: \.self) { index in
                    Circle()
                        .stroke(tint.opacity(0.5), lineWidth: 1.4)
                        .frame(width: 150, height: 150)
                        .scaleEffect(pulse ? 1.55 : 0.85)
                        .opacity(pulse ? 0 : 0.7)
                        .animation(
                            .easeOut(duration: 1.8)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.9),
                            value: pulse
                        )
                }

                // Ambient glow
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 190, height: 190)
                    .blur(radius: 28)

                // Glass plate
                Circle()
                    .fill(.clear)
                    .frame(width: 150, height: 150)
                    .liquidOnboardingGlass(in: Circle(), tint: tint.opacity(0.16), interactive: true)

                // Check badge with drawn checkmark
                ZStack {
                    Circle()
                        .fill(tint)
                        .frame(width: 96, height: 96)
                        .shadow(color: tint.opacity(0.5), radius: 22, y: 10)

                    CheckmarkShape()
                        .trim(from: 0, to: checkProgress)
                        .stroke(.black, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                        .frame(width: 42, height: 34)
                }
                .scaleEffect(badgeScale)
                .opacity(badgeOpacity)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear { if isActive { runEntrance() } }
        .onChange(of: isActive) { _, nowActive in
            if nowActive {
                runEntrance()
            } else {
                resetEntrance()
            }
        }
    }

    private func runEntrance() {
        resetEntrance()

        withAnimation(.interpolatingSpring(stiffness: 190, damping: 16).delay(0.12)) {
            badgeScale = 1
            badgeOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.5).delay(0.32)) {
            checkProgress = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            pulse = true
        }
    }

    private func resetEntrance() {
        pulse = false
        checkProgress = 0
        badgeScale = 0.4
        badgeOpacity = 0
    }
}

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

// MARK: - Bottom Content

private struct BottomContentView: View {
    let page: OnboardingPage
    let pageIndex: Int
    let pageCount: Int
    let routeSummary: String
    let continueTitle: String
    let canGoBack: Bool
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            TextContentView(page: page, subtitle: routeSummary)

            IndicatorView(currentIndex: pageIndex, count: pageCount, tint: page.tint)

            HStack(spacing: 12) {
                if canGoBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .liquidOnboardingGlass(in: Circle(), tint: .white.opacity(0.08), interactive: true)
                    }
                    .buttonStyle(OnboardingPressButtonStyle())
                    .transition(.scale.combined(with: .opacity))
                }

                Button(action: onContinue) {
                    HStack(spacing: 9) {
                        Text(continueTitle)
                            .font(.system(size: 17, weight: .bold))

                        Image(systemName: pageIndex == pageCount - 1 ? "checkmark" : "arrow.right")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(page.tint, in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.42), lineWidth: 1))
                    .shadow(color: page.tint.opacity(0.32), radius: 18, y: 10)
                }
                .buttonStyle(OnboardingPressButtonStyle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
        .background {
            VariableGlassBlur(tint: page.tint)
        }
        .animation(.interpolatingSpring(stiffness: 170, damping: 22), value: pageIndex)
    }
}

private struct TextContentView: View {
    let page: OnboardingPage
    let subtitle: String

    var body: some View {
        VStack(spacing: 9) {
            Label(page.eyebrow, systemImage: page.symbolName)
                .font(.system(size: 13, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(page.tint)
                .id("label-\(page.id)")
                .contentTransition(.opacity)

            Text(page.title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .id("title-\(page.id)")
                .transition(.opacity.combined(with: .move(edge: .bottom)))

            Text(subtitle)
                .font(.system(size: 15, weight: .semibold))
                .lineSpacing(3)
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.center)
                .frame(minHeight: 40)
                .padding(.horizontal, 16)
                .id("subtitle-\(page.id)-\(subtitle)")
                .contentTransition(.opacity)
        }
        .animation(.interpolatingSpring(stiffness: 170, damping: 22), value: page.id)
        .animation(.easeInOut(duration: 0.18), value: subtitle)
    }
}

private struct IndicatorView: View {
    let currentIndex: Int
    let count: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == currentIndex ? tint : Color.white.opacity(0.22))
                    .frame(width: index == currentIndex ? 26 : 8, height: 8)
                    .opacity(index == currentIndex ? 1 : 0.55)
                    .shadow(color: index == currentIndex ? tint.opacity(0.45) : .clear, radius: 7, y: 2)
            }
        }
        .animation(.interpolatingSpring(stiffness: 170, damping: 22), value: currentIndex)
    }
}

private struct VariableGlassBlur: View {
    let tint: Color

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(.ultraThinMaterial)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.22),
                            tint.opacity(0.08),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .black.opacity(0.08),
                            .black.opacity(0.56),
                            .black.opacity(0.84)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, 42)
                .padding(.top, 1)
        }
        .mask(
            UnevenRoundedRectangle(
                topLeadingRadius: 36,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 36,
                style: .continuous
            )
            .ignoresSafeArea(edges: .bottom)
        )
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - Backdrop

private struct OnboardingAmbientBackdrop: View {
    let page: OnboardingPage

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "#020305"),
                    Color(hex: "#0B0E13"),
                    Color(hex: "#020305")
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [page.tint.opacity(0.24), .clear],
                center: page.glowAnchor,
                startRadius: 20,
                endRadius: 420
            )

            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill((index.isMultiple(of: 2) ? page.tint : CABSColors.color(for: "CLS")).opacity(0.1))
                    .frame(width: CGFloat(180 + index * 72), height: CGFloat(180 + index * 72))
                    .blur(radius: 48)
                    .offset(x: CGFloat(index * 86 - 132), y: CGFloat(index * 130 - 210))
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .animation(.interpolatingSpring(stiffness: 170, damping: 22), value: page.id)
    }
}

// MARK: - Micro Components

private struct OnboardingPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.interpolatingSpring(stiffness: 240, damping: 18), value: configuration.isPressed)
    }
}

// MARK: - Liquid Glass Helpers

private extension View {
    @ViewBuilder
    func liquidOnboardingGlass<S: InsettableShape>(
        in shape: S,
        tint: Color = .clear,
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26, *) {
            if interactive {
                self.glassEffect(.regular.tint(tint).interactive(true), in: shape)
            } else {
                self.glassEffect(.regular.tint(tint), in: shape)
            }
        } else {
            self
                .background(
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay(shape.fill(tint.opacity(0.6)))
                        .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 0.8))
                )
        }
    }
}
