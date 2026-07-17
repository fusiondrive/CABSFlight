//
//  CABSBottomSheetView.swift
//  CABSFlight
//
//  Custom Liquid Glass bottom sheet that slides up when the user taps a
//  bus stop on the map. Displays arriving buses in a Bento grid and
//  exposes the "Track via Dynamic Island" button that fires
//  CABSLiveActivityManager.
//

import SwiftUI
import ActivityKit

// MARK: - Unified Prediction Model

private struct SheetPrediction: Identifiable {
    let id: String
    let routeCode: String
    let busLabel: String
    let timeDisplay: String
    let rawSeconds: Double
    let isDelayed: Bool

    var color: Color { CABSColors.color(for: routeCode) }
}

// MARK: - Bottom Sheet View

/// Bottom sheet displayed when the user selects a stop annotation on the map.
@available(iOS 26, *)
struct CABSBottomSheetView: View {

    @Bindable var viewModel: BusViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - State Properties

    /// Vertical translation of the card. Owns the card's on-screen position
    /// through both the live drag *and* the release animation, so there is no
    /// snap-back-then-animate seam. Deliberately `@State` (not `@GestureState`)
    /// because a `@GestureState` resets the instant the finger lifts, which
    /// would erase the position the release spring needs to animate from.
    @State private var dragOffset: CGFloat = 0

    /// Measured height of the card, used to send it fully off-screen on
    /// dismissal and to normalize the release velocity for the spring.
    @State private var panelHeight: CGFloat = 0

    /// Bumped whenever the selection changes. An in-flight interactive-dismiss
    /// completion checks this before clearing `selectedStop`, so re-selecting a
    /// stop mid-dismiss can never close the freshly opened sheet.
    @State private var dismissGeneration = 0

    /// True only while a drag is physically in progress. Auto-resets via
    /// `@GestureState`, so if the system cancels the drag without an `onEnded`
    /// (the classic "stuck offset" bug) `onChange` snaps the card back.
    @GestureState private var isDragging = false

    /// Set by `onEnded` so the `isDragging → false` safety net knows a release
    /// was already handled and must not fight the dismiss/settle it started.
    @State private var didHandleRelease = false

    private let manager = CABSLiveActivityManager.shared

    // MARK: - Derived Data

    private var stop: Stop? { viewModel.selectedStop }

    /// Maps the service's live Prediction objects into display-ready SheetPredictions.
    private var predictions: [SheetPrediction] {
        viewModel.currentStopPredictions.prefix(4).map { pred in
            SheetPrediction(
                id: pred.id,
                routeCode: pred.routeCode,
                busLabel: "Bus \(pred.vehicleID)",
                timeDisplay: pred.timeDisplay,
                rawSeconds: pred.arrivalSeconds,
                isDelayed: false
            )
        }
    }

    private var leadPrediction: SheetPrediction? { predictions.first }

    private var accentColor: Color {
        leadPrediction?.color
            ?? viewModel.selectedRoute?.officialColor
            ?? .blue
    }

    private var isTrackingThisStop: Bool {
        manager.isTracking && manager.trackedStop == stop?.name
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            panel
        }
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: viewModel.selectedStop?.id) { _, newID in
            // Invalidate any pending interactive-dismiss completion.
            dismissGeneration += 1

            // Only a switch to *another* stop (card stays mounted) returns the
            // offset to rest, and it animates rather than snapping. On a real
            // dismissal (newID == nil) the view unmounts, so we leave dragOffset
            // exactly where it is — the exit animates from the current position
            // and the next presentation remounts fresh at 0. This is what
            // removes the old "jump back up, then slide out" artifact.
            guard newID != nil else { return }
            withAnimation(Theme.Anim.sheetSettle) { dragOffset = 0 }
        }
        .onChange(of: isDragging) { _, dragging in
            guard !dragging else { return }
            // Safety net: a drag that ends without `onEnded` (system cancel)
            // must not leave the card parked mid-screen. If `onEnded` already
            // ran, it set `didHandleRelease` and started its own animation —
            // don't fight it.
            if didHandleRelease {
                didHandleRelease = false
            } else if dragOffset != 0 {
                settle(initialVelocity: 0)
            }
        }
    }

    // MARK: - Panel

    private var panel: some View {
        LiquidBottomCardShell(tintColor: accentColor) {
            dragHandle

            VStack(alignment: .leading, spacing: 20) {
                stopHeader
                predictionsSection
                trackButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
        .offset(y: dragOffset)
        .opacity(panelOpacity)
        .gesture(dismissGesture)
    }

    /// Subtle fade as the card slides off, so the silent unmount at the end of
    /// an interactive dismiss is imperceptible. Stays near-opaque during normal
    /// dragging so the card doesn't wash out under the finger.
    private var panelOpacity: Double {
        guard panelHeight > 0, dragOffset > 0 else { return 1 }
        let progress = min(dragOffset / panelHeight, 1)
        return 1 - Double(progress) * 0.6
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        Capsule()
            .fill(Color.primary.opacity(0.2))
            .frame(width: Theme.UI.dragHandleWidth, height: Theme.UI.dragHandleHeight)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Stop Header

    private var stopHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("STATION")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Text(stop?.name ?? "")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                dismissDiscretely()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Predictions Section

    @ViewBuilder
    private var predictionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Approaching Buses")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            if predictions.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    Text("No buses approaching right now.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else {
                let columns = [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ]
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(predictions) { pred in
                        let isThisTracked = manager.isTracking
                            && manager.trackedStop == stop?.name
                            && manager.trackedRouteCode == pred.routeCode
                        PredictionBentoCard(prediction: pred, isTracked: isThisTracked) {
                            Task { await trackPrediction(pred) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Track Button

    @ViewBuilder
    private var trackButton: some View {
        let noTarget = leadPrediction == nil && !isTrackingThisStop

        Button {
            Task {
                if isTrackingThisStop {
                    await manager.stopTracking()
                } else if let pred = leadPrediction {
                    await trackPrediction(pred)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(
                    systemName: isTrackingThisStop
                        ? "bell.slash.fill"
                        : "bell.badge.fill"
                )
                .font(.system(size: 17, weight: .semibold))

                Text(isTrackingThisStop ? "Stop Tracking" : "Track via Dynamic Island")
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(isTrackingThisStop ? Color.primary : Color.white)
            .background {
                if isTrackingThisStop {
                    RoundedRectangle(cornerRadius: Theme.UI.bentoCardCornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.UI.bentoCardCornerRadius, style: .continuous)
                                .stroke(.white.opacity(0.25), lineWidth: 1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: Theme.UI.bentoCardCornerRadius, style: .continuous)
                        .fill(accentColor.gradient)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.UI.bentoCardCornerRadius, style: .continuous)
                                .fill(.white.opacity(0.14))
                        )
                        .shadow(color: accentColor.opacity(0.5), radius: 10, x: 0, y: 4)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(noTarget)
        .opacity(noTarget ? 0.5 : 1.0)
        .animation(Theme.Anim.selectionFeedback, value: isTrackingThisStop)
    }

    // MARK: - Dismiss Gesture

    /// Drag-to-dismiss. Tracks the finger 1:1 downward, rubber-bands upward past
    /// rest, and on release decides dismiss vs. settle from momentum
    /// (`predictedEndTranslation`) and velocity — never a fixed distance.
    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { value in
                dragOffset = resistedOffset(value.translation.height)
            }
            .onEnded { value in
                didHandleRelease = true
                let translation = value.translation.height
                let velocity = value.velocity.height
                let projectedEnd = value.predictedEndTranslation.height

                // Momentum-based intent: a flick projects far even from a short
                // drag; a slow 60 pt drag projects ~60 pt and stays. A minimum
                // real travel guards against an accidental fast twitch.
                let projectedFarEnough = projectedEnd > Theme.UI.sheetDismissProjection
                let flicked = velocity > Theme.UI.sheetFlickVelocity
                let movedEnough = translation > Theme.UI.sheetMinDismissTravel

                if (projectedFarEnough || flicked) && movedEnough {
                    dismissInteractively(releaseVelocity: velocity)
                } else {
                    settle(initialVelocity: velocity)
                }
            }
    }

    // MARK: - Dismiss / Settle

    /// Discrete (non-gesture) dismissal — close button. The removal transition
    /// (owned by `sheetTransition` in `LiquidGlassView`) plays with the single
    /// `sheetDismiss` / `sheetReduced` transaction; no offset animation.
    private func dismissDiscretely() {
        dismissGeneration += 1
        withAnimation(reduceMotion ? Theme.Anim.sheetReduced : Theme.Anim.sheetDismiss) {
            viewModel.selectedStop = nil
        }
    }

    /// Interactive dismissal continuing the finger's motion. Reduce Motion
    /// skips the spatial slide and falls back to the discrete fade.
    private func dismissInteractively(releaseVelocity: CGFloat) {
        guard !reduceMotion else {
            dismissDiscretely()
            return
        }

        dismissGeneration += 1
        let generation = dismissGeneration
        let dismissingID = stop?.id
        let target = panelHeight > 0 ? panelHeight : 600

        // Hand the release velocity straight to the spring (normalized by the
        // remaining distance) so the card continues at the finger's speed —
        // no seam between drag and animation.
        let remaining = max(target - dragOffset, 1)
        let normalizedVelocity = Double(releaseVelocity / remaining)

        withAnimation(Theme.Anim.sheetRelease(initialVelocity: normalizedVelocity)) {
            dragOffset = target
        } completion: {
            // The card is off-screen and faded; unmount silently (no transition
            // transaction). Guard against a re-selection during the slide.
            guard generation == dismissGeneration,
                  viewModel.selectedStop?.id == dismissingID else { return }
            viewModel.selectedStop = nil
        }
    }

    /// Return the card to rest, carrying the release velocity into the spring.
    private func settle(initialVelocity: CGFloat) {
        let normalizedVelocity = dragOffset > 0
            ? Double(-initialVelocity / max(dragOffset, 1))
            : 0
        let animation = reduceMotion
            ? Theme.Anim.sheetReduced
            : Theme.Anim.sheetRelease(initialVelocity: normalizedVelocity)
        withAnimation(animation) { dragOffset = 0 }
    }

    // MARK: - Drag Geometry

    /// Downward drags track the finger 1:1; upward drags past the resting
    /// position meet progressive rubber-band resistance instead of a hard stop.
    private func resistedOffset(_ raw: CGFloat) -> CGFloat {
        guard raw < 0 else { return raw }
        let dimension = panelHeight > 0 ? panelHeight : 600
        return -rubberband(-raw, dimension: dimension)
    }

    /// Apple's rubber-band curve: the further past the bound, the less the card
    /// follows (see `Designing Fluid Interfaces`, WWDC 2018).
    private func rubberband(_ overshoot: CGFloat, dimension: CGFloat, constant: CGFloat = 0.55) -> CGFloat {
        (overshoot * dimension * constant) / (dimension + constant * overshoot)
    }

    // MARK: - Tracking Helper

    private func trackPrediction(_ pred: SheetPrediction) async {
        let arrival = Date().addingTimeInterval(pred.rawSeconds)
        await manager.startTracking(
            stopName: stop?.name ?? "",
            routeCode: pred.routeCode,
            arrivalDate: arrival,
            isDelayed: pred.isDelayed
        )
    }
}

// MARK: - Prediction Bento Card

/// Compact card in the 2-column Bento grid. Tapping a card tracks that specific
/// route, allowing the user to choose between multiple simultaneously arriving buses.
@available(iOS 26, *)
private struct PredictionBentoCard: View {
    let prediction: SheetPrediction
    let isTracked: Bool
    let onTrack: () -> Void

    var body: some View {
        Button(action: onTrack) {
            VStack(alignment: .leading, spacing: 8) {
                // Route badge and active-tracking indicator
                HStack(alignment: .center) {
                    Text(prediction.routeCode)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(prediction.color, in: Capsule())

                    Spacer()

                    if isTracked {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(prediction.color)
                            .symbolEffect(.pulse)
                    }
                }

                // Large ETA countdown
                Text(prediction.timeDisplay)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(prediction.isDelayed ? Color.orange : Color.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // Bus identifier
                Text(prediction.busLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(Theme.UI.bentoCardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                isTracked
                    ? .regular.tint(prediction.color.opacity(0.22)).interactive(true)
                    : .regular.interactive(true),
                in: RoundedRectangle(cornerRadius: Theme.UI.bentoCardCornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.UI.bentoCardCornerRadius, style: .continuous)
                    .strokeBorder(
                        isTracked ? prediction.color.opacity(0.55) : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(Theme.Anim.selectionFeedback, value: isTracked)
    }
}
