import SwiftUI
import TechFinderCore

/// The light meter: ISO, aperture and shutter speed as three glass pills.
///
/// Right (arrow or swipe) raises a value: higher ISO, a higher f-number, a faster shutter. Steps are full
/// stops or thirds, as set in Settings. ISO is always set by hand, and so is one of aperture and
/// shutter (lock icon); the meter gives the other (A). Tapping a value lists the values within the
/// equipment limits to pick from; picking or moving the metered value makes it the one set by hand.
/// Values outside the equipment limits turn orange.
///
/// Held sideways the row stays where it is, so to the viewer the pills stand upright; their text turns
/// to read upright, the arrows then point up and down (up raises), and the order runs shutter, aperture,
/// ISO from the viewer's top.
struct MeterBar: View {
    @Binding var settings: ExposureSettings
    let solution: ExposureSolution
    let limits: ExposureLimits
    /// The calibrated spot reading at ISO 100, or nil before the first reading.
    let ev100: Double?
    /// Most of the metered spot is clipped white, so the metered value is only a bound.
    let readingIsClipped: Bool
    /// Thirds of a stop per step.
    let step: Int
    /// How the phone is turned: the text and value lists turn by this to read upright.
    let rotation: Angle

    /// Taller held sideways, where the pill's height is the width the turned text has.
    static func height(turned: Bool) -> CGFloat { turned ? 52 : 40 }

    var body: some View {
        // The viewer's top is the screen's right when turned left (+90°), its left when turned right.
        let axes: [ExposureAxis] = rotation.degrees < 0 ? [.shutter, .aperture, .iso] : [.iso, .aperture, .shutter]
        HStack(spacing: 8) {
            ForEach(axes, id: \.self) { dial($0) }
        }
        .animation(ViewfinderView.turn, value: rotation)
    }

    private func dial(_ axis: ExposureAxis) -> some View {
        switch axis {
        // The raw reading, for comparing with a handheld meter.
        case .iso: dial(.iso, caption: ev100.map { String(format: "ISO · EV %.1f", $0) } ?? "ISO")
        case .aperture: dial(.aperture, caption: "Aperture")
        case .shutter: dial(.shutter, caption: "Shutter")
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
            value: isMetered && ev100 == nil ? "—" : solution.label(axis),
            badge: badge,
            isWarning: solution.isOutsideLimits(axis, limits) || (isMetered && readingIsClipped),
            canLower: direction > 0 ? index > range.lowerBound : index < range.upperBound,
            canRaise: direction > 0 ? index < range.upperBound : index > range.lowerBound,
            change: { steps in settings.step(axis, by: steps * direction, thirdsPerStep: step, from: solution) },
            choices: choices(axis, current: index),
            selectedChoice: index,
            select: { settings.set(axis, to: $0) },
            rotation: rotation
        )
        .accessibilityIdentifier("meter-\(axis.rawValue)")
    }

    /// Every value within the equipment limits, in thirds, plus the current one if it is outside them.
    /// Like the arrows, lower values are at the top: small ISOs, wide apertures, slow shutter speeds.
    private func choices(_ axis: ExposureAxis, current: Int) -> [(index: Int, label: String)] {
        let range = limits.range(axis)
        let indices = min(range.lowerBound, current)...max(range.upperBound, current)
        let values = indices.filter { range.contains($0) || $0 == current }.map { ($0, ExposureScale.label(axis, $0)) }
        // Shutter indices run fast to slow.
        return axis == .shutter ? values.reversed() : values
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
    /// Values to pick from when the value is tapped.
    let choices: [(index: Int, label: String)]
    let selectedChoice: Int
    let select: (Int) -> Void
    let rotation: Angle

    /// Steps already applied during the current swipe.
    @State private var swipeSteps = 0
    @State private var ticks = 0
    @State private var showsChoices = false
    @GestureState private var isTouching = false

    private let stepDistance: CGFloat = 26

    /// Turned right, the screen's left end is the viewer's top, so the left arrow and a swipe to the
    /// left raise the value.
    private var sign: Int { rotation.degrees < 0 ? -1 : 1 }

    var body: some View {
        HStack(spacing: 0) {
            arrow("chevron.left", enabled: sign > 0 ? canLower : canRaise) { apply(-sign) }

            valueArea

            arrow("chevron.right", enabled: sign > 0 ? canRaise : canLower) { apply(sign) }
        }
        .frame(height: MeterBar.height(turned: rotation != .zero))
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

    /// The caption and value. Tapping opens the list of choices; swiping steps it.
    private var valueArea: some View {
        valueLabel
            .onTapGesture { showsChoices = true }
            .gesture(swipe)
            .popover(isPresented: $showsChoices) {
                // The list opens in screen space, so it turns on its own to read upright.
                let isTurned = rotation != .zero
                ChoiceList(title: caption, choices: choices, selected: selectedChoice) { index in
                    select(index)
                    ticks += 1
                    showsChoices = false
                }
                .rotationEffect(rotation)
                .frame(width: isTurned ? ChoiceList.size.height : ChoiceList.size.width,
                       height: isTurned ? ChoiceList.size.width : ChoiceList.size.height)
                .presentationCompactAdaptation(.popover)
            }
    }

    /// Caption and value. Held sideways they turn to read upright, laid out across the pill's height.
    private var valueLabel: some View {
        GeometryReader { geometry in
            let isTurned = rotation != .zero
            labels
                .frame(width: isTurned ? geometry.size.height - 8 : geometry.size.width,
                       height: isTurned ? geometry.size.width : geometry.size.height)
                .rotationEffect(rotation)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .animation(ViewfinderView.turn, value: rotation)
        .contentShape(Rectangle())
    }

    private var labels: some View {
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
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            Text(value)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(isWarning ? Color.orange : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
                let steps = sign * Int((drag.translation.width / stepDistance).rounded(.towardZero))
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

/// A short list to pick a value from, scrolled to the current one.
private struct ChoiceList: View {
    let title: String
    let choices: [(index: Int, label: String)]
    let selected: Int
    let pick: (Int) -> Void

    static let size = CGSize(width: 160, height: 300)

    var body: some View {
        ScrollViewReader { proxy in
            List(choices, id: \.index) { choice in
                Button {
                    pick(choice.index)
                } label: {
                    HStack {
                        Text(choice.label)
                            .monospacedDigit()
                        Spacer()
                        if choice.index == selected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .id(choice.index)
                .accessibilityAddTraits(choice.index == selected ? .isSelected : [])
            }
            .listStyle(.plain)
            .task {
                // After the list's first layout, or it has no rows to scroll to yet.
                await Task.yield()
                proxy.scrollTo(selected, anchor: .center)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityIdentifier("choices")
    }
}
