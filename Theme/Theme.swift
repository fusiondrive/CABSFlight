//
//  Theme.swift
//  CABSFlight
//

import SwiftUI

/// Central design-token registry for the CABSFlight Liquid Glass UI.
/// All layout constants, animation presets, and map parameters live here
/// to eliminate magic numbers across view files.
enum Theme {

    // MARK: - Colors

    /// Onboarding accent tints. Other legacy color/spacing/typography tokens
    /// were removed once the classic UI they served was deleted (Phase 0).
    static let accent          = Color(hex: "#007AFF")
    static let accentSecondary = Color(hex: "#FFD60A")

    // MARK: - UI Layout Constants

    /// Dimension tokens for the Liquid Glass card shell, map annotations,
    /// and interactive elements throughout the app.
    enum UI {
        /// Fallback corner radius for the glass card shell. The shell now uses
        /// container-concentric corners that follow the device's screen radius;
        /// this value is only a reference for non-concentric contexts (previews).
        static let sheetCornerRadius: CGFloat = 38
        /// Corner radius shared by bento prediction cards and the track button.
        static let bentoCardCornerRadius: CGFloat = 16
        /// Inner bottom breathing space between the card's content and the glass
        /// edge. Sized to clear the larger concentric bottom-corner curve so a
        /// full-width control (the track button) isn't clipped. Home-indicator
        /// clearance is handled separately via the live safe-area inset.
        static let sheetContentBottomPadding: CGFloat = 28
        /// Horizontal edge padding applied to `LiquidBottomCardShell`.
        static let sheetHorizontalPadding: CGFloat = 8
        /// Outer bottom spacing between the card shell and the physical screen edge.
        static let sheetBottomPadding: CGFloat = 16
        /// Bottom padding applied to floating route buttons when no info card is visible.
        static let floatingButtonsBottomPadding: CGFloat = 50
        /// Projected end-translation (pts) past which a downward sheet drag
        /// commits to dismissal. Uses `predictedEndTranslation` (momentum), so a
        /// flick dismisses early while a slow 60 pt drag settles back.
        static let sheetDismissProjection: CGFloat = 150
        /// Downward release velocity (pts/s) that dismisses regardless of
        /// distance — a fast flick.
        static let sheetFlickVelocity: CGFloat = 900
        /// Minimum actual downward travel (pts) before any dismissal is allowed,
        /// so an accidental fast twitch can't close the sheet.
        static let sheetMinDismissTravel: CGFloat = 20
        /// Width of the drag handle pill at the top of the stop sheet.
        static let dragHandleWidth: CGFloat = 40
        /// Height of the drag handle pill.
        static let dragHandleHeight: CGFloat = 4
        /// Diameter of the inner white fill circle on a stop annotation.
        static let stopMarkerSize: CGFloat = 12
        /// Width of the route-colored stroke ring on a stop annotation.
        static let stopMarkerStrokeWidth: CGFloat = 2.5
        /// Diameter of the bus vehicle marker circle.
        static let busMarkerSize: CGFloat = 22
        /// Hit-test frame size for stop map annotations.
        static let stopAnnotationFrame: CGFloat = 36
        /// Hit-test frame size for bus vehicle map annotations.
        static let busAnnotationFrame: CGFloat = 44
        /// Inner content padding for bento prediction cards.
        static let bentoCardPadding: CGFloat = 14
        /// Opacity of the route-color tint passed to `glassEffect` on the card shell.
        static let glassShellTintOpacity: CGFloat = 0.1
    }

    // MARK: - Map Constants

    /// Coordinate span and camera-offset tokens for MapKit positioning.
    enum Map {
        /// Degree span (latitude and longitude) when the camera zooms to a selected stop.
        static let closeUpSpan: Double = 0.012
        /// Fraction of `closeUpSpan` subtracted from the stop's latitude so the pin
        /// appears in the upper portion of the visible area above the bottom sheet.
        static let closeUpVerticalOffsetFraction: Double = 0.25
        /// Static `safeAreaPadding` applied to the Map view at all times.
        /// A constant value prevents the map frame from resizing when the bottom
        /// sheet appears, eliminating the iOS 17+ MapKit camera teleport bug.
        static let bottomPadding: CGFloat = 100
        /// Degree span used when "Focus Bus" zooms the camera to a vehicle.
        static let zoomToBusSpan: Double = 0.008
    }

    // MARK: - Animation Presets

    /// Named `Animation` instances for consistent motion throughout the Liquid Glass UI.
    enum Anim {
        // MARK: Stop bottom sheet
        //
        // Single-ownership model: the sheet's `.transition` defines *how* it
        // enters/leaves; exactly one transaction below defines the *timing* for
        // each interaction. No call-site stacks a second animation on the same
        // change.

        /// Presentation of the stop sheet (tap a stop). Owns the insertion.
        static let sheetPresent = Animation.spring(response: 0.42, dampingFraction: 0.82)
        /// Discrete, non-gesture dismissal — close button, map tap, route
        /// switch. Owns the removal transition.
        static let sheetDismiss = Animation.spring(response: 0.34, dampingFraction: 0.9)
        /// Non-velocity reposition of the sheet to rest, e.g. returning the
        /// drag offset to 0 when the user switches to a different stop.
        static let sheetSettle = Animation.spring(response: 0.4, dampingFraction: 0.85)
        /// Reduced-motion replacement for every sheet spring: a short opacity
        /// crossfade with no spatial spring.
        static let sheetReduced = Animation.easeOut(duration: 0.2)

        /// Velocity-carrying spring for an interactive drag release (settle-back
        /// or dismiss). `initialVelocity` is the release velocity normalized by
        /// the remaining distance, handing the finger's momentum straight to the
        /// spring so there's no seam between drag and animation. Critically
        /// damped-ish (no overshoot) — a sheet shouldn't bounce.
        static func sheetRelease(initialVelocity: Double) -> Animation {
            .interpolatingSpring(stiffness: 300, damping: 30, initialVelocity: initialVelocity)
        }

        /// Spring for route chip selection in the horizontal scroll strip.
        static let routeChip = Animation.spring(response: 0.35, dampingFraction: 0.7)
        /// Smooth ease-in-out for camera fly-to transitions (route framing, stop dismiss).
        static let cameraFly = Animation.easeInOut(duration: 0.5)
        /// Slightly slower camera fly when tapping a stop annotation, matching the
        /// sheet slide-up timing for a more deliberate, cohesive feel.
        static let stopCameraFly = Animation.easeInOut(duration: 0.6)
        /// Insertion spring for the floating info card sliding up from the bottom edge.
        static let infoCardInsertion = Animation.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0)
        /// Cross-fade when swapping between info card content states (vehicle ↔ stop ↔ route).
        static let infoCardFade = Animation.easeInOut(duration: 0.15)
        /// Spring for showing/hiding the bottom overlay stack and info card.
        static let bottomOverlay = Animation.spring(response: 0.4, dampingFraction: 0.8)
        /// Visual feedback for annotation and button pressed/selected state changes.
        static let selectionFeedback = Animation.easeOut(duration: 0.2)
        /// Snappy spring for MapKit annotation tap press feedback.
        static let mapTap = Animation.spring(response: 0.2, dampingFraction: 0.6)
        /// Repeating pulse for the LIVE badge indicator dot.
        static let liveBadgePulse = Animation.easeInOut(duration: 1).repeatForever(autoreverses: true)
    }
}

// MARK: - Map Item Press Modifier

/// Applies persistent press and selection feedback to MapKit `Annotation` views.
///
/// Two constraints this modifier addresses:
///
/// 1. **`ButtonStyle.isPressed` is consumed by MapKit.** MapKit installs a
///    `UIGestureRecognizer` on every annotation host at the UIKit layer,
///    consuming the touch before SwiftUI's button machinery sees it. This modifier
///    bypasses that by using `DragGesture(minimumDistance: 0)` with
///    `.simultaneousGesture` — it fires on raw touch-down/up without competing
///    with MapKit's tap recogniser.
///
/// 2. **Selection state must persist beyond the tap instant.** The visual effect
///    stays active while `isPressed || isSelected`, so the annotation remains
///    highlighted for the full duration of its selection.
///
/// Usage:
///
///     LiquidStationView(...)
///         .contentShape(Rectangle())
///         .mapItemPressEffect(isSelected: viewModel.selectedStop?.id == stop.id) {
///             viewModel.selectStop(stop)
///         }
struct MapItemPressEffect: ViewModifier {
    /// Whether this annotation is the currently active/selected item.
    let isSelected: Bool
    /// Fired on touch-up (guarded against accidental short drags).
    let action: () -> Void

    @State private var isPressed = false

    func body(content: Content) -> some View {
        let active = isPressed || isSelected
        return content
            .scaleEffect(active ? 0.96 : 1.0)
            .brightness(active ? -0.15 : 0)
            .animation(Theme.Anim.mapTap, value: active)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !isPressed { isPressed = true } }
                    .onEnded { value in
                        isPressed = false
                        // Treat as a tap only when the finger barely moved;
                        // ignore genuine map-pan drags.
                        let t = value.translation
                        guard abs(t.width) < 10, abs(t.height) < 10 else { return }
                        action()
                    }
            )
    }
}

extension View {
    /// Attaches persistent press and selection feedback to a MapKit `Annotation` view.
    /// The `action` closure replaces `.onTapGesture` — do not combine both.
    func mapItemPressEffect(isSelected: Bool, action: @escaping () -> Void) -> some View {
        modifier(MapItemPressEffect(isSelected: isSelected, action: action))
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red:     Double(r) / 255,
            green:   Double(g) / 255,
            blue:    Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
