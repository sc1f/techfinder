import SwiftUI
import TechFinderCore

/// The bottom control: a lens carousel, or an Add Lens button when the library is empty.
struct ControlBar: View {
    @Environment(LibraryStore.self) private var library
    let present: (ViewfinderView.Sheet) -> Void
    @Binding var tip: HoldTip?
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
                LensCarousel(tip: $tip, rotation: rotation)
            }
        }
    }
}

/// The system segmented control on a glass capsule, like the Photos app's bottom bar. On iOS 26 the
/// selection lifts into a clear glass lens while pressed or dragged.
private struct NativeLensPicker: View {
    @Environment(LibraryStore.self) private var library
    let rotation: Angle

    private var selection: Binding<Lens.ID?> {
        Binding(get: { library.selectedLensID }, set: { library.selectedLensID = $0 })
    }

    var body: some View {
        Picker("Lens", selection: selection) {
            ForEach(library.lenses) { lens in
                label(for: lens)
                    .accessibilityLabel(lens.displayName)
                    .tag(Optional(lens.id))
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .fixedSize()
        .padding(4)
        .glassSurface(Capsule())
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func label(for lens: Lens) -> some View {
        if rotation == .zero {
            Text("\(lens.focalLengthLabel)mm")
        } else {
            // Segments only show plain text or images, so turned labels are drawn as images.
            Image(uiImage: TurnedLabel.image(lens.focalLengthLabel, angle: rotation))
        }
    }
}

/// Renders a short label as a template image turned by a quarter turn, for segmented control segments.
enum TurnedLabel {
    static func image(_ text: String, angle: Angle) -> UIImage {
        let font = UIFont.systemFont(ofSize: 15, weight: .semibold).withMonospacedDigits()
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.black])
        let textSize = attributed.size()
        let size = CGSize(width: ceil(textSize.height), height: ceil(textSize.width))
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            cg.translateBy(x: size.width / 2, y: size.height / 2)
            cg.rotate(by: angle.radians)
            attributed.draw(at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2))
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

/// A circular glass icon button whose icon turns with the phone.
struct RoundGlassControl: View {
    let systemImage: String
    let rotation: Angle
    let tip: HoldTip
    @Binding var shownTip: HoldTip?
    var size: CGFloat = 48
    var isOn = false
    let action: () -> Void

    var body: some View {
        HoldTipControl(tip: tip, shownTip: $shownTip, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.375, weight: .medium))
                .foregroundStyle(isOn ? Color.accentColor : .white)
                .rotationEffect(rotation)
                .animation(.smooth, value: rotation)
                .frame(width: size, height: size)
        }
        .glassSurface(Circle(), interactive: true)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Saved lenses, wide to long, on a centred glass pill that hugs them and grows from the middle.
///
/// When they fit, the highlight slides to the selected lens; dragging moves a glass lens under the finger
/// and selects the lens beneath it. When there are more lenses than fit, the pill spans the width and
/// works like the Camera app's mode switcher: the selected lens sits in the centre, dragging slides the
/// row, and releasing snaps to the nearest lens (a flick carries on).
///
/// Positions are computed from measured label widths only. Measuring positions instead would feed the
/// row's own offset back into layout and never settle.
private struct LensCarousel: View {
    @Environment(LibraryStore.self) private var library
    @Binding var tip: HoldTip?
    let rotation: Angle

    @State private var widths: [Lens.ID: CGFloat] = [:]
    @State private var isDragging = false
    /// Where the glass lens sits while dragging a pill that fits, in row coordinates.
    @State private var fingerX: CGFloat = 0
    /// Scrolling mode: centre of the selected lens when the drag began. The row is laid out from it
    /// while dragging so live selection changes don't move it.
    @State private var dragAnchor: CGFloat?
    @State private var dragOffset: CGFloat = 0

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
                .glassSurface(Capsule(), interactive: true)
                .contentShape(Capsule())
                .gesture(slide(fits: fits))
                .position(x: available / 2, y: height / 2)
                .animation(.smooth(duration: 0.3), value: trackWidth)
        }
        .frame(height: height)
        .accessibilityElement(children: .contain)
        .accessibilityAdjustableAction { direction in
            step(direction == .increment ? 1 : -1)
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

            items
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

    private var items: some View {
        let format = library.selectedFormat
        return HStack(spacing: spacing) {
            ForEach(library.lenses) { lens in
                let fov = FieldOfView(focalLength: lens.focalLength, format: format)
                item(for: lens, tip: HoldTip(title: lens.displayName, detail: "\(fov.anglesLabel) · \(fov.equivalentLabel)"))
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                        widths[lens.id] = width
                    }
            }
        }
        .fixedSize()
    }

    private func item(for lens: Lens, tip lensTip: HoldTip) -> some View {
        let isSelected = lens.id == library.selectedLensID
        // Turned sideways, "65mm" would be taller than the track, so only the number turns.
        let isTurned = rotation != .zero

        return HoldTipControl(tip: lensTip, shownTip: $tip) {
            withAnimation(settle) { library.selectedLensID = lens.id }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(lens.focalLengthLabel)
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                if !isTurned {
                    Text("mm")
                        .font(.system(size: 10, weight: .medium))
                        .opacity(0.7)
                }
            }
            .fixedSize()
            .rotationEffect(rotation)
            .animation(.smooth, value: rotation)
            .foregroundStyle(isSelected ? Color.accentColor : .white)
            .padding(.horizontal, 12)
            .frame(minWidth: minItemWidth)
            .frame(height: 40)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Dragging

    private func slide(fits: Bool) -> some Gesture {
        DragGesture(minimumDistance: 5)
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
