//
//  UserPreferences.swift
//  CABSFlight
//
//  Manages persistent user preferences for route visibility and onboarding state.
//

import Foundation
import Observation

/// Observable preferences manager backed by UserDefaults
@Observable
@MainActor
final class UserPreferences {
    // MARK: - Properties

    /// Route IDs the user has chosen to display (empty = show all)
    var visibleRouteIDs: Set<String> {
        didSet { persistRouteIDs() }
    }

    /// Whether the user has completed the onboarding flow
    var hasSeenOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasSeenOnboarding, forKey: Keys.hasSeenOnboarding) }
    }

    // MARK: - Constants

    private enum Keys {
        static let visibleRouteIDs = "visibleRouteIDs"
        static let hasSeenOnboarding = "hasSeenOnboarding"
    }

    // MARK: - Initialization

    init() {
        let raw = UserDefaults.standard.string(forKey: Keys.visibleRouteIDs) ?? ""
        let ids = raw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
        self.visibleRouteIDs = Set(ids)
        self.hasSeenOnboarding = UserDefaults.standard.bool(forKey: Keys.hasSeenOnboarding)
    }

    // MARK: - Public Methods

    /// Returns true if the given route should appear on the map
    func isRouteVisible(id: String) -> Bool {
        visibleRouteIDs.isEmpty || visibleRouteIDs.contains(id)
    }

    /// Flip a single route between visible / hidden
    func toggleRouteVisibility(id: String) {
        if visibleRouteIDs.contains(id) {
            visibleRouteIDs.remove(id)
        } else {
            visibleRouteIDs.insert(id)
        }
    }

    /// Bulk-set visible routes (used by onboarding)
    func setVisibleRoutes(_ ids: Set<String>) {
        visibleRouteIDs = ids
    }

    /// Mark the onboarding flow as completed
    func completeOnboarding() {
        hasSeenOnboarding = true
    }

    // MARK: - Private

    private func persistRouteIDs() {
        let joined = visibleRouteIDs.sorted().joined(separator: ",")
        UserDefaults.standard.set(joined, forKey: Keys.visibleRouteIDs)
    }
}
