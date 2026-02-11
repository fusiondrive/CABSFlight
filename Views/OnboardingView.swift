//
//  OnboardingView.swift
//  CABSFlight
//
//  First-launch onboarding flow: Welcome → Route picker → Ready.
//

import SwiftUI

struct OnboardingView: View {
    var viewModel: BusViewModel
    var preferences: UserPreferences

    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0
    @State private var selectedRouteIDs: Set<String> = []

    var body: some View {
        TabView(selection: $currentPage) {
            welcomePage.tag(0)
            chooseRoutesPage.tag(1)
            readyPage.tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(Color(hex: "#0A0A0A").ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            // App Icon – Liquid Glass Style
            ZStack {
                // Outer ambient glow
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [Theme.accent.opacity(0.3), .clear],
                            center: .center,
                            startRadius: 30,
                            endRadius: 120
                        )
                    )
                    .frame(width: 200, height: 200)

                // Glass body
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#1C1C1E"), Color(hex: "#0A0A0A")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.3), .white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .overlay(
                        // Glossy highlight
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.2), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .padding(2)
                    )
                    .shadow(color: Theme.accent.opacity(0.3), radius: 20, y: 10)

                // Bus icon
                Image(systemName: "bus.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Theme.accent.opacity(0.5), radius: 8, y: 2)
            }

            VStack(spacing: 12) {
                Text("Welcome to")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))

                Text("CABS Flight")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)

                Text("The smoothest way to get around campus.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            // Swipe hint
            HStack(spacing: 6) {
                Text("Swipe to continue")
                    .font(.system(size: 14, weight: .medium))
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white.opacity(0.25))
            .padding(.bottom, 60)
        }
    }

    // MARK: - Page 2: Choose Routes

    private var chooseRoutesPage: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("Choose Your Lines")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Text("Select the routes you ride.\nYou can always change this later.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 60)

            // Route List
            ScrollView {
                VStack(spacing: 12) {
                    if viewModel.allRoutes.isEmpty {
                        // Loading state
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.white)
                            Text("Loading routes...")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .padding(.top, 40)
                    } else {
                        ForEach(viewModel.allRoutes) { route in
                            OnboardingRouteRow(
                                route: route,
                                isSelected: selectedRouteIDs.contains(route.id),
                                onTap: { toggleRoute(route.id) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            // Skip hint
            Text("Skip to show all routes")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.3))
                .padding(.bottom, 50)
        }
    }

    // MARK: - Page 3: Ready

    private var readyPage: some View {
        VStack(spacing: 24) {
            Spacer()

            // Celebration icon
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.08))
                    .frame(width: 160, height: 160)

                Circle()
                    .fill(Theme.accent.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.accent, Color(hex: "#0055CC")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Theme.accent.opacity(0.4), radius: 12, y: 4)
            }

            VStack(spacing: 12) {
                Text("All Set!")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)

                Text(summaryText)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            // Start Exploring button
            Button(action: finish) {
                Text("Start Exploring")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.accent)
                    )
                    .shadow(color: Theme.accent.opacity(0.4), radius: 12, y: 6)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 60)
        }
    }

    // MARK: - Helpers

    private var summaryText: String {
        if selectedRouteIDs.isEmpty {
            return "Your map will show all available routes."
        } else {
            let sorted = selectedRouteIDs.sorted()
            return "Your map is set to show \(sorted.joined(separator: ", "))."
        }
    }

    private func toggleRoute(_ id: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if selectedRouteIDs.contains(id) {
                selectedRouteIDs.remove(id)
            } else {
                selectedRouteIDs.insert(id)
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

// MARK: - Route Row Component

struct OnboardingRouteRow: View {
    let route: Route
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Color dot
                Circle()
                    .fill(route.officialColor)
                    .frame(width: 14, height: 14)
                    .shadow(color: route.officialColor.opacity(0.4), radius: 4)

                // Route code
                Text(route.id)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, alignment: .leading)

                // Route name
                Text(route.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)

                Spacer()

                // Checkmark circle
                ZStack {
                    Circle()
                        .stroke(
                            isSelected ? route.officialColor : Color.white.opacity(0.2),
                            lineWidth: 2
                        )
                        .frame(width: 26, height: 26)

                    if isSelected {
                        Circle()
                            .fill(route.officialColor)
                            .frame(width: 26, height: 26)

                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? route.officialColor.opacity(0.12) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                isSelected ? route.officialColor.opacity(0.4) : Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}
