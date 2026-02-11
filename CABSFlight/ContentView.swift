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

// MARK: - Preview

#Preview {
    ContentView()
}
