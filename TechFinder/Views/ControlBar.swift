import SwiftUI
import TechFinderCore

/// The bottom control: a lens carousel, or an Add Lens button when the library is empty.
struct ControlBar: View {
    @Environment(LibraryStore.self) private var library
    @Binding var sheet: ViewfinderView.Sheet?
    @Binding var tip: HoldTip?
    let rotation: Angle

    var body: some View {
        if library.lenses.isEmpty {
            Button {
                sheet = .newLens
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
            LensCarousel(tip: $tip, rotation: rotation)
        }
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

/// Saved lenses, wide to long, with the selected lens always in the centre, like the Camera app's
/// mode switcher.
///
/// Tap a lens to bring it to the centre. Drag to slide the row: the lens under the centre is selected as
/// it passes, and on release the row snaps to the nearest lens (a flick carries on). While dragging, the
/// centre highlight lifts into a clear glass lens over the labels.
private struct LensCarousel: View {
    @Environment(LibraryStore.self) private var library
    @Binding var tip: HoldTip?
    let rotation: Angle

    @State private var itemFrames: [Lens.ID: CGRect] = [:]
    /// Centre of the selected lens when the drag began; the row is laid out from it while dragging so
    /// live selection changes don't move it.
    @State private var dragAnchor: CGFloat?
    @State private var dragOffset: CGFloat = 0

    private static let space = "LensCarousel"
    private let height: CGFloat = 48
    private let settle = Animation.spring(response: 0.35, dampingFraction: 0.85)

    private var isDragging: Bool { dragAnchor != nil }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let selectedFrame = library.selectedLensID.flatMap { itemFrames[$0] }
            let anchor = dragAnchor ?? selectedFrame?.midX ?? width / 2
            let thumbWidth = selectedFrame?.width ?? 56

            ZStack {
                // Resting highlight, behind the labels.
                Capsule()
                    .fill(.white.opacity(0.16))
                    .frame(width: thumbWidth, height: 40)
                    .opacity(isDragging ? 0 : 1)

                items
                    .frame(width: width, height: height, alignment: .leading)
                    .offset(x: width / 2 - anchor + dragOffset)
                    .mask {
                        // Fade lenses out towards the ends of the track.
                        LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                               .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                    }

                // Lifted glass lens, over the labels while dragging.
                Capsule()
                    .fill(.white.opacity(0.04))
                    .glassLens(Capsule(), isActive: isDragging)
                    .frame(width: thumbWidth + 10, height: 44)
                    .scaleEffect(isDragging ? 1.08 : 0.9)
                    .opacity(isDragging ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .frame(width: width, height: height)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isDragging)
            .animation(.smooth(duration: 0.2), value: thumbWidth)
        }
        .frame(height: height)
        .clipShape(Capsule())
        .glassSurface(Capsule(), interactive: true)
        .contentShape(Capsule())
        .simultaneousGesture(slide)
        .accessibilityElement(children: .contain)
        .accessibilityAdjustableAction { direction in
            step(direction == .increment ? 1 : -1)
        }
    }

    private var items: some View {
        let format = library.selectedFormat
        return HStack(spacing: 4) {
            ForEach(library.lenses) { lens in
                let fov = FieldOfView(focalLength: lens.focalLength, format: format)
                item(for: lens, tip: HoldTip(title: lens.displayName, detail: "\(fov.anglesLabel) · \(fov.equivalentLabel)"))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frame in
                        itemFrames[lens.id] = frame
                    }
            }
        }
        .fixedSize()
        .coordinateSpace(.named(Self.space))
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
            .frame(minWidth: 56)
            .frame(height: 40)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Sliding

    private var slide: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                let anchor = dragAnchor ?? currentCenter
                dragAnchor = anchor
                let position = rubberBanded(anchor - value.translation.width)
                dragOffset = anchor - position
                if let id = lens(nearestTo: position), id != library.selectedLensID {
                    library.selectedLensID = id
                }
            }
            .onEnded { value in
                guard let anchor = dragAnchor else { return }
                let target = lens(nearestTo: clamped(anchor - value.predictedEndTranslation.width))
                withAnimation(settle) {
                    if let target { library.selectedLensID = target }
                    dragAnchor = nil
                    dragOffset = 0
                }
            }
    }

    private var centers: [(id: Lens.ID, x: CGFloat)] {
        library.lenses.compactMap { lens in itemFrames[lens.id].map { (lens.id, $0.midX) } }
    }

    private var currentCenter: CGFloat {
        library.selectedLensID.flatMap { itemFrames[$0]?.midX } ?? 0
    }

    private func lens(nearestTo x: CGFloat) -> Lens.ID? {
        centers.min { abs($0.x - x) < abs($1.x - x) }?.id
    }

    private func clamped(_ x: CGFloat) -> CGFloat {
        guard let first = centers.first?.x, let last = centers.last?.x else { return x }
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
