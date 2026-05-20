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
            // Confirm the OS actually activated it. If activityState is anything
            // other than .active the Dynamic Island will not appear — check the
            // widget extension embedding steps below.
            print("""
            [CABSLiveActivityManager] ✓ Activity.request succeeded
              id           : \(currentActivity?.id ?? "nil")
              activityState: \(String(describing: currentActivity?.activityState))
              stop         : \(stopName)  route: \(routeCode)
              arrivalDate  : \(arrivalDate)
            If the Dynamic Island is still not visible, the widget extension
            .appex bundle is not embedded in the app — see setup steps below.
            """)
        } catch let authError as ActivityAuthorizationError {
            switch authError {
            case .denied:
                print("""
                [CABSLiveActivityManager] ✗ denied
                  → The user disabled Live Activities for this app.
                    Fix: Settings › \(Bundle.main.bundleIdentifier ?? "CABSFlight") › Live Activities → enable.
                """)
            case .unsupportedTarget:
                // This is the error you'll see when the widget extension is not
                // wired up correctly.  All three items below must be true:
                //
                //   1. CABSFlightAttributes.swift is compiled into the WIDGET EXTENSION target
                //      Xcode → project navigator → select CABSFlightAttributes.swift
                //      → File Inspector (⌥⌘1) → Target Membership → tick the widget extension
                //
                //   2. NSSupportsLiveActivities = YES is in the HOST APP's Info.plist
                //      CABSFlight/Info.plist → add key NSSupportsLiveActivities, value YES
                //
                //   3. The widget bundle @main registers CABSFlightLiveActivity()
                //      CABSFlightWidgetBundle.body must contain: CABSFlightLiveActivity()
                print("""
                [CABSLiveActivityManager] ✗ unsupportedTarget
                  → Widget extension is not configured correctly. See inline comments above.
                    failureReason    : \(authError.failureReason ?? "nil")
                    recoverySuggestion: \(authError.recoverySuggestion ?? "nil")
                """)
            case .unentitled:
                print("""
                [CABSLiveActivityManager] ✗ unentitled
                  → The app is missing the Live Activities entitlement.
                    failureReason: \(authError.failureReason ?? "nil")
                """)
            case .unsupported:
                print("""
                [CABSLiveActivityManager] ✗ unsupported
                  → This device does not support Live Activities (requires iOS 16.1+).
                """)
            case .targetMaximumExceeded:
                print("[CABSLiveActivityManager] ✗ targetMaximumExceeded — call stopTracking() before starting a new one.")
            case .globalMaximumExceeded:
                print("[CABSLiveActivityManager] ✗ globalMaximumExceeded — too many system-wide activities running.")
            case .attributesTooLarge:
                print("[CABSLiveActivityManager] ✗ attributesTooLarge — CABSFlightAttributes exceeds the 4 KB limit.")
            case .visibility:
                print("[CABSLiveActivityManager] ✗ visibility — Live Activities can only be started from the foreground.")
            default:
                print("[CABSLiveActivityManager] ✗ ActivityAuthorizationError: \(authError) | \(authError.localizedDescription)")
            }
        } catch {
            let ns = error as NSError
            print("""
            [CABSLiveActivityManager] ✗ unexpected error
              description : \(error.localizedDescription)
              domain      : \(ns.domain)
              code        : \(ns.code)
              userInfo    : \(ns.userInfo)
            """)
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
