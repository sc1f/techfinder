import SwiftUI
import TechFinderCore

/// The light meter: ISO, aperture and shutter speed as three glass pills.
///
/// Each value steps by a third of a stop with its arrows or by swiping along it. ISO is always set by
/// hand. Tapping aperture or shutter holds it (lock icon) and the other follows the meter (A). Moving
/// the metered value by hand sets both by hand. Values outside the equipment limits turn orange.
struct MeterBar: View {
    @Binding var settings: ExposureSettings
    let solution: ExposureSolution
    let limits: ExposureLimits
    let hasReading: Bool

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

        return MeterDial(
            caption: caption,
            // The metered value is unknown until the first light reading.
            value: isMetered && !hasReading ? "—" : solution.label(axis),
            badge: badge,
            isWarning: solution.isOutsideLimits(axis, limits),
            canStepDown: index > range.lowerBound,
            canStepUp: index < range.upperBound,
            step: { delta in settings.step(axis, by: delta, from: solution) },
            lock: axis == .iso ? nil : { settings.lock(axis, from: solution) }
        )
        .accessibilityIdentifier("meter-\(axis.rawValue)")
    }
}

/// One exposure value with step arrows. Swipe along the value to change it by several thirds.
private struct MeterDial: View {
    enum Badge { case locked, metered }

    let caption: String
    let value: String
    let badge: Badge?
    let isWarning: Bool
    let canStepDown: Bool
    let canStepUp: Bool
    let step: (Int) -> Void
    let lock: (() -> Void)?

    /// Thirds already applied during the current swipe.
    @State private var swipeSteps = 0
    @State private var ticks = 0

    private let stepDistance: CGFloat = 22

    var body: some View {
        HStack(spacing: 0) {
            arrow("chevron.left", enabled: canStepDown) { apply(-1) }

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
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)

                Text(value)
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(isWarning ? Color.orange : .white)
                    .contentTransition(.numericText())
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

            arrow("chevron.right", enabled: canStepUp) { apply(1) }
        }
        .frame(height: GlassButtonMetrics.pillHeight)
        .glassSurface(Capsule(), interactive: true)
        .sensoryFeedback(.selection, trigger: ticks)
        .animation(.smooth(duration: 0.2), value: value)
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
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(enabled ? 0.7 : 0.2))
                .frame(width: 24)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let steps = Int((value.translation.width / stepDistance).rounded(.towardZero))
                if steps != swipeSteps {
                    apply(steps - swipeSteps)
                    swipeSteps = steps
                }
            }
            .onEnded { _ in swipeSteps = 0 }
    }

    private func apply(_ delta: Int) {
        guard delta != 0 else { return }
        step(delta)
        ticks += 1
    }
}
