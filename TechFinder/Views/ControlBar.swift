import SwiftUI
import TechFinderCore

/// The bottom control: a lens carousel, or an Add Lens button when the library is empty.
struct ControlBar: View {
    @Environment(LibraryStore.self) private var library
    let present: (ViewfinderView.Sheet) -> Void
    let rotation: Angle

    var body: some View {
        if library.lenses.isEmpty {
            Button {
                present(.newLens)
            } label: {
                Label("Add Lens", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .frame(height: 48)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassSurface(Capsule(), interactive: true)
        } else {
            // Apple's segmented control, with its Liquid Glass lens, when the lenses fit; the sliding
            // carousel when there are more than fit.
            ViewThatFits(in: .horizontal) {
                NativeLensPicker(rotation: rotation)
                LensCarousel(rotation: rotation)
            }
        }
    }
}

/// The system segmented control. On iOS 26 the selection lifts into a clear glass lens that magnifies
/// the labels while pressed or dragged, like the Photos app's bottom bar.
private struct NativeLensPicker: View {
    @Environment(LibraryStore.self) private var library
    let rotation: Angle

    /// The rotation the labels are drawn at. It trails `rotation` so the labels can fade out, turn while
    /// hidden and fade back in; segments can't animate their images turning.
    @State private var labelRotation: Angle?
    @State private var labelOpacity = 1.0

    private var selection: Binding<Lens.ID?> {
        Binding(get: { library.selectedLensID }, set: { library.selectedLensID = $0 })
    }

    var body: some View {
        Picker("Lens", selection: selection) {
            ForEach(library.lenses) { lens in
                Image(uiImage: LensLabel.image(lens.focalLengthLabel, angle: labelRotation ?? rotation))
                    .accessibilityLabel(lens.displayName)
                    .tag(Optional(lens.id))
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .fixedSize()
        .opacity(labelOpacity)
        .frame(maxWidth: .infinity)
        .onChange(of: rotation) { _, newRotation in
            withAnimation(.easeIn(duration: 0.1)) {
                labelOpacity = 0.3
            } completion: {
                labelRotation = newRotation
                withAnimation(.easeOut(duration: 0.2)) { labelOpacity = 1 }
            }
        }
    }
}

/// Lens labels for segmented control segments, which only show plain text or images. Upright it reads
/// "65mm"; turned, just the number turns in the same space, so the control never changes size.
enum LensLabel {
    private static let number = UIFont.systemFont(ofSize: 16, weight: .semibold).withMonospacedDigits()
    private static let unit = UIFont.systemFont(ofSize: 10, weight: .medium)

    static func image(_ focalLength: String, angle: Angle) -> UIImage {
        let upright = NSMutableAttributedString(string: focalLength, attributes: [.font: number, .foregroundColor: UIColor.black])
        upright.append(NSAttributedString(string: "mm", attributes: [.font: unit, .foregroundColor: UIColor.black.withAlphaComponent(0.7)]))
        let turned = NSAttributedString(string: focalLength, attributes: [.font: number, .foregroundColor: UIColor.black])
        let uprightSize = upright.size()
        let turnedSize = turned.size()
        // Room for either: the upright width, and the turned number's length as height.
        let size = CGSize(width: ceil(max(uprightSize.width, turnedSize.height)),
                          height: ceil(max(uprightSize.height, turnedSize.width)))
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            cg.translateBy(x: size.width / 2, y: size.height / 2)
            if angle == .zero {
                upright.draw(at: CGPoint(x: -uprightSize.width / 2, y: -uprightSize.height / 2))
            } else {
                cg.rotate(by: angle.radians)
                turned.draw(at: CGPoint(x: -turnedSize.width / 2, y: -turnedSize.height / 2))
            }
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
                .fill(.white.opacity(0.16))
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

            // Lifted glass lens, over the labels while dragging.
            Capsule()
                .fill(.white.opacity(0.04))
                .glassLens(Capsule(), isActive: isDragging)
                .frame(width: thumbWidth + 10, height: 44)
                .scaleEffect(isDragging ? 1.08 : 0.9)
                .offset(x: lensX - (thumbWidth + 10) / 2)
                .opacity(isDragging ? 1 : 0)
                .allowsHitTesting(false)
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
            .foregroundStyle(isSelected ? Color.accentColor : .white)
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
