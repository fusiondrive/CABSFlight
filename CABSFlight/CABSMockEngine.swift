//
//  CABSMockEngine.swift
//  CABSFlight
//
//  A fully self-contained mock environment for the CABSFlight transit app.
//
//  ──────────────────────────────────────────────────────────────────────────
//  ARCHITECTURAL CONTRACT — DO NOT BREAK
//  ──────────────────────────────────────────────────────────────────────────
//  • This file MUST remain free of any networking, URLSession, Combine
//    publishers backed by remote sources, or third-party SDKs.
//  • It is the *only* source of truth for the UI layer during development
//    and previews. Real networking lives elsewhere and conforms to the same
//    public shape (MockBus / MockStopPrediction) when introduced.
//  • Treat this engine as a frozen contract: extend by adding, never by
//    mutating existing model fields or method signatures.
//  ──────────────────────────────────────────────────────────────────────────
//
//  Created for the OSU West Campus Loop simulation.
//

import Foundation
import SwiftUI
import CoreLocation
import Observation

// MARK: - Public Data Models

/// A bus moving along a route. Mirrors the shape we expect from the live
/// CABS endpoint so the UI layer can be swapped over without refactors.
public struct MockBus: Identifiable, Hashable, Sendable {
    public let id: String
    public let routeName: String
    /// Hex string (e.g. "#C8102E") so this struct stays UI-framework agnostic.
    /// Use `MockBus.uiColor` from the SwiftUI extension below at render time.
    public let colorHex: String
    public var currentCoordinate: CLLocationCoordinate2D

    public init(
        id: String,
        routeName: String,
        colorHex: String,
        currentCoordinate: CLLocationCoordinate2D
    ) {
        self.id = id
        self.routeName = routeName
        self.colorHex = colorHex
        self.currentCoordinate = currentCoordinate
    }

    public static func == (lhs: MockBus, rhs: MockBus) -> Bool {
        lhs.id == rhs.id
            && lhs.routeName == rhs.routeName
            && lhs.colorHex == rhs.colorHex
            && lhs.currentCoordinate.latitude == rhs.currentCoordinate.latitude
            && lhs.currentCoordinate.longitude == rhs.currentCoordinate.longitude
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(currentCoordinate.latitude)
        hasher.combine(currentCoordinate.longitude)
    }
}

/// An arrival prediction at a particular stop for a particular route.
public struct MockStopPrediction: Identifiable, Hashable, Sendable {
    public let id: String
    public let stopName: String
    public let routeCode: String
    public var timeToArrivalInSeconds: Int

    public init(
        id: String = UUID().uuidString,
        stopName: String,
        routeCode: String,
        timeToArrivalInSeconds: Int
    ) {
        self.id = id
        self.stopName = stopName
        self.routeCode = routeCode
        self.timeToArrivalInSeconds = timeToArrivalInSeconds
    }
}

// MARK: - The Engine

/// `CABSMockEngine` simulates the CABS realtime feed.
///
/// On `start()` it begins a 1-second tick that:
///   1. Decrements every prediction's `timeToArrivalInSeconds`.
///   2. Recycles any prediction that hits zero with a fresh random ETA.
///   3. Advances each bus one step along its hardcoded loop path.
///
/// The engine is `@Observable` so SwiftUI views simply read its published
/// properties and re-render — there is no Combine plumbing to maintain.
@Observable
@MainActor
public final class CABSMockEngine {

    // MARK: Public observable state

    public private(set) var buses: [MockBus]
    public private(set) var predictions: [MockStopPrediction]
    public private(set) var isRunning: Bool = false
    /// Monotonic tick count; useful for previews/snapshots.
    public private(set) var tickCount: Int = 0

    // MARK: Private internals

    /// Each bus has an index into its loop path. Keyed by bus id.
    private var pathIndices: [String: Int] = [:]
    private var timer: Timer?

    /// The OSU West Campus Loop, expressed as a closed polyline.
    private static let westCampusLoop: [CLLocationCoordinate2D] = [
        .init(latitude: 40.0040, longitude: -83.0305), // Lincoln Tower
        .init(latitude: 40.0028, longitude: -83.0355), // Carmack Rd
        .init(latitude: 40.0001, longitude: -83.0398), // Kenny Rd / Ackerman
        .init(latitude: 39.9985, longitude: -83.0360), // RPAC West
        .init(latitude: 39.9990, longitude: -83.0305), // Drinko Hall
        .init(latitude: 40.0009, longitude: -83.0285), // Ohio Union
        .init(latitude: 40.0040, longitude: -83.0305)  // back to start
    ]

    // MARK: Init

    public init() {
        let seedBuses: [MockBus] = [
            MockBus(id: "bus-cabs-001", routeName: "CLNS", colorHex: "#C8102E",
                    currentCoordinate: Self.westCampusLoop[0]),
            MockBus(id: "bus-cabs-002", routeName: "EWE",  colorHex: "#1E66F5",
                    currentCoordinate: Self.westCampusLoop[2]),
            MockBus(id: "bus-cabs-003", routeName: "BL",   colorHex: "#137B3F",
                    currentCoordinate: Self.westCampusLoop[4])
        ]
        self.buses = seedBuses
        self.predictions = [
            MockStopPrediction(stopName: "Lincoln Tower",       routeCode: "CLNS", timeToArrivalInSeconds: 240),
            MockStopPrediction(stopName: "RPAC West",           routeCode: "EWE",  timeToArrivalInSeconds: 95),
            MockStopPrediction(stopName: "Ohio Union",          routeCode: "BL",   timeToArrivalInSeconds: 480),
            MockStopPrediction(stopName: "Drinko Hall",         routeCode: "CLNS", timeToArrivalInSeconds: 60),
            MockStopPrediction(stopName: "Kenny Rd / Ackerman", routeCode: "EWE",  timeToArrivalInSeconds: 320)
        ]
        for (i, bus) in seedBuses.enumerated() {
            pathIndices[bus.id] = (i * 2) % Self.westCampusLoop.count
        }
    }

    // MARK: Lifecycle

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    // MARK: Convenience accessors

    public func prediction(forStop stopName: String, routeCode: String) -> MockStopPrediction? {
        predictions.first { $0.stopName == stopName && $0.routeCode == routeCode }
    }

    /// Returns the estimated arrival Date for a (stop, route) pair.
    /// Falls back to +5 min when no matching prediction exists.
    public func estimatedArrival(forStop stopName: String, routeCode: String) -> Date {
        let seconds = prediction(forStop: stopName, routeCode: routeCode)?.timeToArrivalInSeconds ?? 300
        return Date().addingTimeInterval(TimeInterval(seconds))
    }

    // MARK: - Simulation tick

    private func tick() {
        tickCount &+= 1

        predictions = predictions.map { p in
            var next = p
            if next.timeToArrivalInSeconds > 0 {
                next.timeToArrivalInSeconds -= 1
            } else {
                next.timeToArrivalInSeconds = Int.random(in: 240...540)
            }
            return next
        }

        buses = buses.map { bus in
            var moved = bus
            let nodeIndex = pathIndices[bus.id] ?? 0
            let nextIndex = (nodeIndex + 1) % Self.westCampusLoop.count
            let from = Self.westCampusLoop[nodeIndex]
            let to   = Self.westCampusLoop[nextIndex]

            let stepFraction = 0.10
            let newLat = bus.currentCoordinate.latitude
                + (to.latitude - bus.currentCoordinate.latitude) * stepFraction
            let newLng = bus.currentCoordinate.longitude
                + (to.longitude - bus.currentCoordinate.longitude) * stepFraction
            moved.currentCoordinate = CLLocationCoordinate2D(latitude: newLat, longitude: newLng)

            let distLat = abs(newLat - to.latitude)
            let distLng = abs(newLng - to.longitude)
            if distLat < 0.00015 && distLng < 0.00015 {
                pathIndices[bus.id] = nextIndex
                moved.currentCoordinate = to
            }
            return moved
        }
    }
}

// MARK: - SwiftUI Color bridge

public extension MockBus {
    /// SwiftUI Color derived from `colorHex`.
    /// Uses the non-failable Color(hex:) from Theme.swift; falls back to gray
    /// on a malformed string via that initializer's own default path.
    var uiColor: Color {
        Color(hex: colorHex)
    }
}

// MARK: - Preview / Snapshot helpers

public extension CABSMockEngine {
    /// A non-ticking engine with deterministic values for SwiftUI previews.
    static func previewEngine() -> CABSMockEngine {
        CABSMockEngine()
        // Do NOT call start() — previews should be static.
    }
}
