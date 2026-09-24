import SwiftUI
import TechFinderCore

/// The light meter: ISO, aperture and shutter speed as three glass pills.
///
/// Right (arrow or swipe) raises a value: higher ISO, a higher f-number, a faster shutter. Steps are full
/// stops or thirds, as set in Settings. ISO is always set by hand, and so is one of aperture and
/// shutter (lock icon); the meter gives the other (A). Tapping or moving the metered value makes it the
/// one set by hand. Values outside the equipment limits turn orange.
struct MeterBar: View {
    @Binding var settings: ExposureSettings
    let solution: ExposureSolution
    let limits: ExposureLimits
    let hasReading: Bool
    /// Most of the metered spot is clipped white, so the metered value is only a bound.
    let readingIsClipped: Bool
    /// Thirds of a stop per step.
    let step: Int

    static let height: CGFloat = 40

    var body: some View {
        HStack(spacing: 8) {
            dial(.iso, caption: "ISO")
            dial(.aperture, caption: "Aperture")
            dial(.shutter, caption: "Shutter")
        }
    }

    private func dial(_ axis: ExposureAxis, caption: String) -> some View {
        let range = ExposureScale.range(axis)
        let index = solution.index(axis)
        let isMetered = settings.meteredAxis == axis
        let badge: MeterDial.Badge? = settings.lockedAxis == axis ? .locked : (isMetered ? .metered : nil)
        // Shutter indices run from fast to slow, so "higher" (faster) is a lower index.
        let direction = axis == .shutter ? -1 : 1

        return MeterDial(
            caption: caption,
            // The metered value is unknown until the first light reading.
            value: isMetered && !hasReading ? "—" : solution.label(axis),
            badge: badge,
            isWarning: solution.isOutsideLimits(axis, limits) || (isMetered && readingIsClipped),
            canLower: direction > 0 ? index > range.lowerBound : index < range.upperBound,
            canRaise: direction > 0 ? index < range.upperBound : index > range.lowerBound,
            change: { steps in settings.step(axis, by: steps * step * direction, from: solution) },
            lock: axis == .iso ? nil : { settings.lock(axis, from: solution) }
        )
        .accessibilityIdentifier("meter-\(axis.rawValue)")
    }
}

/// One exposure value with step arrows. Swipe along the value to change it by several steps.
private struct MeterDial: View {
    enum Badge { case locked, metered }

    let caption: String
    let value: String
    let badge: Badge?
    let isWarning: Bool
    let canLower: Bool
    let canRaise: Bool
    /// Raises (positive) or lowers (negative) the value by a number of steps.
    let change: (Int) -> Void
    let lock: (() -> Void)?

    /// Steps already applied during the current swipe.
    @State private var swipeSteps = 0
    @State private var ticks = 0
    @GestureState private var isTouching = false

    private let stepDistance: CGFloat = 26

    var body: some View {
        HStack(spacing: 0) {
            arrow("chevron.left", enabled: canLower) { apply(-1) }

            VStack(spacing: 0) {
                HStack(spacing: 3) {
                    Text(caption)
                    switch badge {
                    case .locked:
                        Image(systemName: "lock.fill")
                            .foregroundStyle(Color.accentColor)
                    case .metered:
                        Text("A")
                            .fontWeight(.bold)
                            .foregroundStyle(Color.accentColor)
                    case nil:
                        EmptyView()
                    }
                }
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)

                Text(value)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isWarning ? Color.orange : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                guard let lock else { return }
                lock()
                ticks += 1
            }
            .gesture(swipe)

            arrow("chevron.right", enabled: canRaise) { apply(1) }
        }
        .frame(height: MeterBar.height)
        // Plain glass: interactive glass stretches with the finger, which a swipe control shouldn't.
        // A faint highlight shows the touch instead, without changing the pill's size.
        .glassSurface(Capsule())
        .overlay(Capsule().fill(.white.opacity(isTouching ? 0.08 : 0)).allowsHitTesting(false))
        .simultaneousGesture(DragGesture(minimumDistance: 0).updating($isTouching) { _, touching, _ in touching = true })
        .animation(.easeOut(duration: 0.12), value: isTouching)
        .sensoryFeedback(.selection, trigger: ticks)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .accessibilityValue(value)
        .accessibilityAdjustableAction { direction in
            apply(direction == .increment ? 1 : -1)
        }
    }

    private func arrow(_ systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(enabled ? 0.7 : 0.2))
                .frame(width: 22)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { drag in
                let steps = Int((drag.translation.width / stepDistance).rounded(.towardZero))
                if steps != swipeSteps {
                    apply(steps - swipeSteps)
                    swipeSteps = steps
                }
            }
            .onEnded { _ in swipeSteps = 0 }
    }

    private func apply(_ steps: Int) {
        guard steps != 0 else { return }
        change(steps)
        ticks += 1
    }
}
