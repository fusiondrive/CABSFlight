//
//  SettingsView.swift
//  CABSFlight
//
//  In-app settings: route visibility toggles and debug tools.
//

import SwiftUI

struct SettingsView: View {
    var viewModel: BusViewModel
    var preferences: UserPreferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - My Routes
                Section {
                    if viewModel.allRoutes.isEmpty {
                        HStack {
                            ProgressView().tint(.secondary)
                            Text("Loading routes...")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        ForEach(viewModel.allRoutes) { route in
                            Toggle(isOn: routeBinding(for: route.id)) {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(route.officialColor)
                                        .frame(width: 12, height: 12)
                                    Text(route.id)
                                        .font(.system(size: 15, weight: .semibold))
                                    Text(route.name)
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .tint(route.officialColor)
                        }
                    }
                } header: {
                    Text("My Routes")
                } footer: {
                    Text("Hidden routes won't appear on the map or in the route bar.")
                }

                // MARK: - Advanced / Debug
                Section("Advanced") {
                    Button {
                        viewModel.loadMockData()
                        dismiss()
                    } label: {
                        Label("Load Mock Buses", systemImage: "ladybug.fill")
                    }

                    Button(role: .destructive) {
                        preferences.setVisibleRoutes([])
                        viewModel.applyRouteFilter()
                    } label: {
                        Label("Reset All Filters", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Route Toggle Binding

    /// Creates a two-way binding that respects the "empty = show all" convention.
    private func routeBinding(for routeID: String) -> Binding<Bool> {
        let allIDs = Set(viewModel.allRoutes.map(\.id))
        return Binding(
            get: {
                preferences.isRouteVisible(id: routeID)
            },
            set: { isOn in
                if preferences.visibleRouteIDs.isEmpty {
                    // Currently in "show all" mode – turning one off means
                    // "show everything except this one."
                    if !isOn {
                        preferences.setVisibleRoutes(allIDs.subtracting([routeID]))
                    }
                } else {
                    if isOn {
                        preferences.visibleRouteIDs.insert(routeID)
                    } else {
                        // Guard: don't allow hiding every route
                        if preferences.visibleRouteIDs.count > 1 {
                            preferences.visibleRouteIDs.remove(routeID)
                        }
                    }
                }
                // If every route is now visible, collapse back to "show all"
                if preferences.visibleRouteIDs == allIDs {
                    preferences.setVisibleRoutes([])
                }
                viewModel.applyRouteFilter()
            }
        )
    }
}
