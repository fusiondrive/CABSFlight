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

    // MARK: - State Properties

    @State private var dragOffset: CGFloat = 0
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
        .onChange(of: viewModel.selectedStop?.id) {
            // Reset drag position whenever the user selects a different stop.
            dragOffset = 0
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
        .offset(y: max(0, dragOffset))
        .gesture(dismissGesture)
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
                withAnimation(Theme.Anim.dismissEaseOut) {
                    viewModel.selectedStop = nil
                }
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

    private var dismissGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if value.translation.height > 0 {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                if value.translation.height > Theme.UI.dragDismissThreshold {
                    withAnimation(Theme.Anim.dismissEaseOut) {
                        viewModel.selectedStop = nil
                    }
                } else {
                    withAnimation(Theme.Anim.dismissSpring) {
                        dragOffset = 0
                    }
                }
            }
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
