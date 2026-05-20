//
//  CABSLiveActivityManager.swift
//  CABSFlight
//
//  Wraps the ActivityKit lifecycle so any view can start, update, or
//  end the CABSFlightLiveActivity with a single async call.
//
//  Usage (from a SwiftUI button action):
//
//      let manager = CABSLiveActivityManager.shared
//
//      // Start
//      await manager.startTracking(stopName: "Lincoln Tower",
//                                  routeCode: "WMC",
//                                  arrivalDate: Date().addingTimeInterval(240))
//      // Update when new ETA comes in
//      await manager.updateETA(newArrivalDate: revisedDate, isDelayed: true)
//
//      // Stop (user dismissed or bus arrived)
//      await manager.stopTracking()
//

import ActivityKit
import Foundation
import SwiftUI

@Observable
@MainActor
final class CABSLiveActivityManager {

    // MARK: - Shared singleton

    static let shared = CABSLiveActivityManager()

    // MARK: - Observable state

    /// Stop name currently being tracked; nil when no activity is live.
    private(set) var trackedStop: String?

    /// Route code currently being tracked; nil when no activity is live.
    private(set) var trackedRouteCode: String?

    /// True while an Activity<CABSFlightAttributes> is running.
    var isTracking: Bool { currentActivity != nil }

    /// Reflects the system Live Activities permission for this app.
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: - Private

    private var currentActivity: Activity<CABSFlightAttributes>?

    private init() {}

    // MARK: - Public API

    /// Starts a new Live Activity for the given stop + route.
    /// Any previously running activity is ended immediately before starting
    /// the new one, so only one activity is ever live at a time.
    func startTracking(
        stopName: String,
        routeCode: String,
        arrivalDate: Date,
        isDelayed: Bool = false
    ) async {
        // Tear down any existing activity before requesting a new one.
        if currentActivity != nil {
            await endCurrentActivity()
        }

        guard areActivitiesEnabled else { return }

        let attributes = CABSFlightAttributes(stopName: stopName, routeCode: routeCode)
        let state = CABSFlightAttributes.ContentState(
            estimatedArrivalTimestamp: arrivalDate,
            isDelayed: isDelayed
        )
        // staleDate: 60 s after the predicted arrival — system clears stale UI.
        let content = ActivityContent(
            state: state,
            staleDate: arrivalDate.addingTimeInterval(60)
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil          // local-only; no push-token refresh needed
            )
            trackedStop = stopName
            trackedRouteCode = routeCode
        } catch {
            // ActivityKit throws when the device can't support activities
            // (simulator without Dynamic Island, Low Power Mode, etc.)
            print("[CABSLiveActivityManager] Could not start Live Activity: \(error)")
        }
    }

    /// Pushes a revised ETA to the running activity.
    /// Call this whenever the bus headway changes meaningfully — not every tick.
    func updateETA(newArrivalDate: Date, isDelayed: Bool = false) async {
        guard let activity = currentActivity else { return }
        let state = CABSFlightAttributes.ContentState(
            estimatedArrivalTimestamp: newArrivalDate,
            isDelayed: isDelayed
        )
        let content = ActivityContent(
            state: state,
            staleDate: newArrivalDate.addingTimeInterval(60)
        )
        await activity.update(content)
    }

    /// Ends the running activity immediately and clears all tracked state.
    func stopTracking() async {
        await endCurrentActivity()
    }

    // MARK: - Private helpers

    private func endCurrentActivity() async {
        guard let activity = currentActivity else { return }
        // nil final state → keep the last displayed ETA visible during dismissal.
        await activity.end(nil, dismissalPolicy: .immediate)
        currentActivity = nil
        trackedStop = nil
        trackedRouteCode = nil
    }
}
