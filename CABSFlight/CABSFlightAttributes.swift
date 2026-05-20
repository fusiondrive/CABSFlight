//
//  CABSFlightAttributes.swift
//  CABSFlight
//
//  The data-exchange contract between the host app and the Live Activity
//  widget extension. Add this file to BOTH targets (app + widget extension)
//  so `ActivityKit` can encode/decode it across the process boundary.
//
//  Design notes:
//  • Static `Attributes` carry the things that never change for the life of
//    the activity — the stop you're waiting at and the route you're tracking.
//  • Dynamic `ContentState` carries a *timestamp* (`estimatedArrivalTimestamp`),
//    not a count. This lets iOS render the countdown using the system's
//    native, battery-friendly `Text(_:style: .relative)` / `.timer` engine
//    so we don't have to push an ActivityKit update every second.
//
//  Update cadence guidance:
//    – Push a new ContentState only when the ETA *changes meaningfully*
//      (delay, early arrival, bus skipped, etc.) or when `isDelayed` flips.
//    – The countdown UI updates itself; ActivityKit pushes do not.
//

import Foundation
import ActivityKit

public struct CABSFlightAttributes: ActivityAttributes {

    // MARK: - Dynamic state
    //
    // `ContentState` is what changes during the life of the activity.
    public struct ContentState: Codable, Hashable {
        /// Absolute moment when the bus is expected at `stopName`. Drives the
        /// native lock-screen countdown via `Text(timerInterval:...)` / `.timer`.
        public var estimatedArrivalTimestamp: Date

        /// True when the bus is running behind its schedule. Used to tint the
        /// countdown and surface a small "Delayed" chip on the Lock Screen.
        public var isDelayed: Bool

        public init(estimatedArrivalTimestamp: Date, isDelayed: Bool) {
            self.estimatedArrivalTimestamp = estimatedArrivalTimestamp
            self.isDelayed = isDelayed
        }
    }

    // MARK: - Static attributes

    /// Human-readable stop, e.g. "Lincoln Tower".
    public let stopName: String
    /// Route shortcode, e.g. "CLNS", "EWE", "BL".
    public let routeCode: String

    public init(stopName: String, routeCode: String) {
        self.stopName = stopName
        self.routeCode = routeCode
    }
}

// MARK: - Convenience helpers for previews & snapshot rendering.

public extension CABSFlightAttributes {
    static var preview: CABSFlightAttributes {
        CABSFlightAttributes(stopName: "Lincoln Tower", routeCode: "CLNS")
    }
}

public extension CABSFlightAttributes.ContentState {
    /// 4 minutes out, on time.
    static var arrivingSoon: CABSFlightAttributes.ContentState {
        .init(estimatedArrivalTimestamp: Date().addingTimeInterval(60 * 4),
              isDelayed: false)
    }

    /// 12 minutes out, delayed.
    static var delayed: CABSFlightAttributes.ContentState {
        .init(estimatedArrivalTimestamp: Date().addingTimeInterval(60 * 12),
              isDelayed: true)
    }
}
