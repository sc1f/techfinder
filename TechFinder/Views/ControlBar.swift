import SwiftUI
import TechFinderCore

/// The lens selector, centred and growing outwards as lenses are added, or an Add Lens button when the
/// library is empty. Its labels turn in place with the phone. A long press opens the lens library.
struct ControlBar: View {
    @Environment(LibraryStore.self) private var library
    let present: (ViewfinderView.Sheet) -> Void
    let rotation: Angle

    @State private var longPresses = 0

    var body: some View {
        Group {
            if library.lenses.isEmpty {
                Button {
                    present(.newLens)
                } label: {
                    Label("Add Lens", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 20)
                        .frame(height: GlassButtonMetrics.pillHeight)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassSurface(Capsule(), interactive: true)
            } else {
                // Apple's segmented control, with its Liquid Glass lens, when the lenses fit, as numbers
                // alone if "mm" makes it too wide; the sliding carousel when there are more than fit.
                ViewThatFits(in: .horizontal) {
                    NativeLensPicker(rotation: rotation, showsUnit: true)
                    NativeLensPicker(rotation: rotation, showsUnit: false)
                    LensCarousel(rotation: rotation)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: GlassButtonMetrics.pillHeight)
        // Held still for half a second: a drag across the lenses moves the finger and still selects.
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
            guard !library.lenses.isEmpty else { return }
            longPresses += 1
            present(.lenses)
        })
        .sensoryFeedback(.impact(weight: .medium), trigger: longPresses)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Lens Library") { present(library.lenses.isEmpty ? .newLens : .lenses) }
        .accessibilityIdentifier("lensSelector")
    }
}

/// A round glass button, as tall as the lens selector, with an icon that turns with the phone and a
/// firm haptic when pressed. `isOn` tints the icon.
struct RoundGlassButton: View {
    let systemImage: String
    let label: String
    var isOn = false
    let rotation: Angle
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var presses = 0

    static let size: CGFloat = GlassButtonMetrics.pillHeight

    var body: some View {
        Button {
            presses += 1
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isOn ? Color.accentColor : .white)
                .opacity(isEnabled ? 1 : 0.35)
                .rotationEffect(rotation)
                .animation(ViewfinderView.turn, value: rotation)
                .frame(width: Self.size - GlassButtonMetrics.padding.leading - GlassButtonMetrics.padding.trailing,
                       height: GlassButtonMetrics.pillLabelHeight)
        }
        .glassButtonStyle(Circle())
        .sensoryFeedback(.impact(weight: .medium, intensity: 1), trigger: presses)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The system segmented control. On iOS 26 the selection lifts into a clear glass lens that magnifies
/// the labels while pressed or dragged, like the Photos app's bottom bar.
private struct NativeLensPicker: View {
    @Environment(LibraryStore.self) private var library
    let rotation: Angle
    /// "65mm" rather than "65".
    let showsUnit: Bool

    /// The angle the labels are drawn at. Segments show images and can't animate them, so when the phone
    /// turns the labels are redrawn frame by frame, turning with the rest of the interface.
    @State private var labelAngle: Double?
    @State private var turning: Task<Void, Never>?

    private var selection: Binding<Lens.ID?> {
        Binding(get: { library.selectedLensID }, set: { library.selectedLensID = $0 })
    }

    var body: some View {
        let angle = labelAngle ?? rotation.radians
        Picker("Lens", selection: selection) {
            ForEach(library.lenses) { lens in
                Image(uiImage: LensLabel.image(lens.focalLengthLabel, showsUnit: showsUnit, angle: angle))
                    .accessibilityLabel(lens.displayName)
                    .tag(Optional(lens.id))
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .fixedSize()
        // Each redrawn label replaces the last outright. Animated, iOS 26 cross-fades every segment
        // through a lighter block, which flashes while the labels turn.
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .onChange(of: rotation) { _, newRotation in
            turn(to: newRotation.radians)
        }
    }

    /// Eases the labels to `target` over about the time the interface's turn spring takes to settle.
    private func turn(to target: Double) {
        turning?.cancel()
        let start = labelAngle ?? target
        turning = Task { @MainActor in
            let duration = 0.4
            let began = Date()
            while !Task.isCancelled {
                let t = min(Date().timeIntervalSince(began) / duration, 1)
                // Ease out, like the tail of a spring.
                let eased = 1 - pow(1 - t, 3)
                labelAngle = start + (target - start) * eased
                if t >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }
}

/// Lens labels for segmented control segments, which only show plain text or images. Upright it reads
/// "65mm"; turned a quarter, just the number, centred in the same space, so the control never changes
/// size. In between, the number turns and moves to the centre as "mm" fades.
enum LensLabel {
    private static let number = UIFont.systemFont(ofSize: 16, weight: .semibold).withMonospacedDigits()
    private static let unit = UIFont.systemFont(ofSize: 10, weight: .medium)

    /// - Parameter angle: Radians; 0 upright, ±π/2 turned.
    static func image(_ focalLength: String, showsUnit: Bool, angle: Double) -> UIImage {
        let turn = min(abs(angle) / (.pi / 2), 1)
        let unitAlpha = 0.7 * max(0, 1 - turn * 2)
        let label = NSMutableAttributedString(string: focalLength, attributes: [.font: number, .foregroundColor: UIColor.black])
        let numberWidth = label.size().width
        if showsUnit {
            label.append(NSAttributedString(string: "mm", attributes: [.font: unit, .foregroundColor: UIColor.black.withAlphaComponent(unitAlpha)]))
        }
        let labelSize = label.size()
        let numberHeight = NSAttributedString(string: focalLength, attributes: [.font: number]).size().height
        // Room for either: the upright label's width, and the turned number's length as height.
        let size = CGSize(width: ceil(max(labelSize.width, numberHeight)),
                          height: ceil(max(labelSize.height, numberWidth)))
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            cg.translateBy(x: size.width / 2, y: size.height / 2)
            cg.rotate(by: angle)
            // Upright the whole label is centred; turned, the number alone is.
            let x = -labelSize.width / 2 + turn * (labelSize.width - numberWidth) / 2
            label.draw(at: CGPoint(x: x, y: -labelSize.height / 2))
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}

private extension UIFont {
    func withMonospacedDigits() -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .featureSettings: [[UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                                UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector]],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

/// Saved lenses, wide to long, on a centred glass pill that hugs them and grows from the middle.
///
/// When they fit, the highlight slides to the selected lens; dragging lifts a clear glass lens that
/// follows the finger, magnifies the lens numbers beneath it and selects the one it is over. Numbers turn
/// in place with the phone without the pill changing size. When there are more lenses than fit, the pill spans the width and
/// works like the Camera app's mode switcher: the selected lens sits in the centre, dragging slides the
/// row, and releasing snaps to the nearest lens (a flick carries on).
///
/// Positions are computed from measured label widths only. Measuring positions instead would feed the
/// row's own offset back into layout and never settle.
private struct LensCarousel: View {
    @Environment(LibraryStore.self) private var library
    let rotation: Angle

    @State private var widths: [Lens.ID: CGFloat] = [:]
    @State private var isDragging = false
    /// Where the glass lens sits while dragging a pill that fits, in row coordinates.
    @State private var fingerX: CGFloat = 0
    /// Scrolling mode: centre of the selected lens when the drag began. The row is laid out from it
    /// while dragging so live selection changes don't move it.
    @State private var dragAnchor: CGFloat?
    @State private var dragOffset: CGFloat = 0
    @GestureState private var isTouching = false

    private let height: CGFloat = 48
    private let inset: CGFloat = 4
    private let spacing: CGFloat = 4
    private let minItemWidth: CGFloat = 56
    private let settle = Animation.spring(response: 0.35, dampingFraction: 0.85)

    /// Each lens's centre and width along the row, starting at 0.
    private var slots: [(id: Lens.ID, center: CGFloat, width: CGFloat)] {
        var x: CGFloat = 0
        return library.lenses.map { lens in
            let width = widths[lens.id] ?? minItemWidth
            defer { x += width + spacing }
            return (lens.id, x + width / 2, width)
        }
    }

    private var rowWidth: CGFloat {
        guard let last = slots.last else { return 0 }
        return last.center + last.width / 2
    }

    var body: some View {
        GeometryReader { geometry in
            let available = geometry.size.width
            let fits = rowWidth + inset * 2 <= available
            let trackWidth = fits ? rowWidth + inset * 2 : available

            track(width: trackWidth, fits: fits)
                .frame(width: trackWidth, height: height)
                .clipShape(Capsule())
                // Plain glass: the lifted lens is the drag feedback, so the pill itself shouldn't stretch.
                .glassSurface(Capsule())
                .contentShape(Capsule())
                // Takes priority over the lens buttons once the finger moves; a plain tap still selects.
                .highPriorityGesture(slide(fits: fits))
                .position(x: available / 2, y: height / 2)
                .animation(.smooth(duration: 0.3), value: trackWidth)
        }
        .frame(height: height)
        .accessibilityElement(children: .contain)
        .accessibilityAdjustableAction { direction in
            step(direction == .increment ? 1 : -1)
        }
        .onChange(of: isTouching) { _, isTouching in
            guard !isTouching, isDragging else { return }
            withAnimation(settle) {
                isDragging = false
                dragAnchor = nil
                dragOffset = 0
            }
        }
    }

    private func track(width: CGFloat, fits: Bool) -> some View {
        let selected = slots.first { $0.id == library.selectedLensID }
        let thumbWidth = selected?.width ?? minItemWidth
        // Leading edge of the row within the track.
        let rowX = fits ? inset : width / 2 - (dragAnchor ?? selected?.center ?? 0) + dragOffset
        let thumbX = fits ? inset + (selected?.center ?? 0) : width / 2
        let lensX = fits && isDragging ? inset + fingerX : thumbX

        return ZStack(alignment: .leading) {
            // Resting highlight, behind the labels.
            Capsule()
                .fill(.white.opacity(0.22))
                .frame(width: thumbWidth, height: 40)
                .offset(x: thumbX - thumbWidth / 2)
                .opacity(isDragging ? 0 : 1)

            // While dragging, lenses near the glass lens grow as if magnified by it.
            items(magnifierX: isDragging ? lensX - rowX : nil)
                .offset(x: rowX)
                .mask {
                    if fits {
                        Rectangle()
                    } else {
                        // Fade lenses out towards the ends of a scrolling row.
                        LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                               .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                    }
                }

            // Lifted glass lens, over the labels while dragging. Only there while dragging: Liquid Glass
            // still blurs what's under it at zero opacity.
            if isDragging {
                Capsule()
                    .fill(.white.opacity(0.04))
                    .glassLens(Capsule(), isActive: true)
                    .frame(width: thumbWidth + 10, height: 44)
                    .offset(x: lensX - (thumbWidth + 10) / 2)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height, alignment: .leading)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isDragging)
        .animation(settle, value: thumbX)
        .animation(.smooth(duration: 0.2), value: thumbWidth)
    }

    /// - Parameter magnifierX: Centre of the glass lens in row coordinates while dragging.
    private func items(magnifierX: CGFloat?) -> some View {
        let centers = Dictionary(uniqueKeysWithValues: slots.map { ($0.id, $0.center) })
        return HStack(spacing: spacing) {
            ForEach(library.lenses) { lens in
                item(for: lens, magnification: magnification(at: centers[lens.id], lens: magnifierX))
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                        widths[lens.id] = width
                    }
            }
        }
        .fixedSize()
    }

    /// Up to 25% larger right under the lens, fading to none a lens-width away.
    private func magnification(at center: CGFloat?, lens: CGFloat?) -> CGFloat {
        guard let center, let lens else { return 1 }
        let reach = minItemWidth
        return 1 + 0.25 * max(0, 1 - abs(center - lens) / reach)
    }

    private func item(for lens: Lens, magnification: CGFloat) -> some View {
        let isSelected = lens.id == library.selectedLensID
        let isTurned = rotation != .zero

        return Button {
            withAnimation(settle) { library.selectedLensID = lens.id }
        } label: {
            ZStack {
                // The upright label always sets the width, so the pill doesn't resize as the phone turns.
                uprightLabel(lens)
                    .opacity(isTurned ? 0 : 1)
                // Turned sideways, "65mm" would be taller than the track, so only the number turns.
                Text(lens.focalLengthLabel)
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .fixedSize()
                    .rotationEffect(rotation)
                    .opacity(isTurned ? 1 : 0)
            }
            .animation(ViewfinderView.turn, value: rotation)
            .scaleEffect(magnification)
            .animation(.smooth(duration: 0.12), value: magnification)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(minWidth: minItemWidth)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lens.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func uprightLabel(_ lens: Lens) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(lens.focalLengthLabel)
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
            Text("mm")
                .font(.system(size: 10, weight: .medium))
                .opacity(0.7)
        }
        .fixedSize()
    }

    // MARK: - Dragging

    private func slide(fits: Bool) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .updating($isTouching) { _, isTouching, _ in isTouching = true }
            .onChanged { value in
                isDragging = true
                let position: CGFloat
                if fits {
                    // The glass lens follows the finger along the row.
                    position = clamped(value.location.x - inset)
                    fingerX = position
                } else {
                    // The row slides under the fixed centre.
                    let anchor = dragAnchor ?? selectedCenter
                    dragAnchor = anchor
                    position = rubberBanded(anchor - value.translation.width)
                    dragOffset = anchor - position
                }
                if let id = lens(nearestTo: position), id != library.selectedLensID {
                    library.selectedLensID = id
                }
            }
            .onEnded { value in
                let target: Lens.ID?
                if fits {
                    target = lens(nearestTo: clamped(value.location.x - inset))
                } else {
                    let anchor = dragAnchor ?? selectedCenter
                    target = lens(nearestTo: clamped(anchor - value.predictedEndTranslation.width))
                }
                withAnimation(settle) {
                    if let target { library.selectedLensID = target }
                    isDragging = false
                    dragAnchor = nil
                    dragOffset = 0
                }
            }
    }

    private var selectedCenter: CGFloat {
        slots.first { $0.id == library.selectedLensID }?.center ?? 0
    }

    private func lens(nearestTo x: CGFloat) -> Lens.ID? {
        slots.min { abs($0.center - x) < abs($1.center - x) }?.id
    }

    private func clamped(_ x: CGFloat) -> CGFloat {
        guard let first = slots.first?.center, let last = slots.last?.center else { return x }
        return min(max(x, first), last)
    }

    /// Lets the row travel a little past the first and last lens with resistance.
    private func rubberBanded(_ x: CGFloat) -> CGFloat {
        let limit = clamped(x)
        return limit + (x - limit) * 0.3
    }

    private func step(_ delta: Int) {
        guard let index = library.lenses.firstIndex(where: { $0.id == library.selectedLensID }) else { return }
        let next = min(max(index + delta, 0), library.lenses.count - 1)
        withAnimation(settle) { library.selectedLensID = library.lenses[next].id }
    }
}
