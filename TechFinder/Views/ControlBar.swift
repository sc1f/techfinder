import SwiftUI
import TechFinderCore

/// Bottom controls: format, the lens strip for one-tap lens changes, and the lens library.
/// Press and hold any of them for a tip.
struct ControlBar: View {
    @Environment(LibraryStore.self) private var library
    @Binding var sheet: ViewfinderView.Sheet?
    @Binding var tip: HoldTip?
    let rotation: Angle

    var body: some View {
        let format = library.selectedFormat

        // Separate glass pieces rather than one merged container, so the lens strip's lifted selection
        // lens isn't absorbed into the strip behind it.
        HStack(spacing: 10) {
            RoundGlassControl(systemImage: "rectangle.dashed", rotation: rotation,
                              tip: HoldTip(title: "Format", detail: "\(format.name) · \(format.dimensionsLabel)"),
                              shownTip: $tip) {
                sheet = .formats
            }
            // The strip hugs its lenses and sits centred in the space between the buttons.
            LensStrip(sheet: $sheet, tip: $tip, rotation: rotation)
                .frame(maxWidth: .infinity)
            RoundGlassControl(systemImage: "camera.aperture", rotation: rotation,
                              tip: HoldTip(title: "Lenses", detail: "Add, edit and choose lenses"),
                              shownTip: $tip) {
                sheet = .lenses
            }
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

/// Saved lenses labelled by focal length, wide to long. Sized to its lenses; scrolls only when they don't fit.
///
/// Works like a segmented control: a thumb slides behind the selected lens, and dragging along the strip
/// selects the lens under the finger while the thumb lifts into a glass lens. When the strip scrolls,
/// horizontal swipes scroll it and dragging starts from the selected lens instead.
private struct LensStrip: View {
    @Environment(LibraryStore.self) private var library
    @Binding var sheet: ViewfinderView.Sheet?
    @Binding var tip: HoldTip?
    let rotation: Angle

    @Namespace private var thumbNamespace
    @State private var chipFrames: [Lens.ID: CGRect] = [:]
    /// Decided when a drag starts and reset by SwiftUI however the drag ends.
    @GestureState private var drag: DragMode = .idle

    private enum DragMode { case idle, selecting, ignoring }
    private var isDragging: Bool { drag == .selecting }

    private static let space = "LensStrip"

    var body: some View {
        Group {
            if library.lenses.isEmpty {
                Button {
                    sheet = .newLens
                } label: {
                    Label("Add Lens", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .frame(height: 48)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                ViewThatFits(in: .horizontal) {
                    chips(dragsFromAnywhere: true)
                        .fixedSize()
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            chips(dragsFromAnywhere: false)
                        }
                        .scrollDisabled(isDragging)
                        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                        // Fade chips out at the ends so an overflowing strip reads as scrollable.
                        .mask {
                            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08),
                                                   .init(color: .black, location: 0.92), .init(color: .clear, location: 1)],
                                           startPoint: .leading, endPoint: .trailing)
                        }
                        .onAppear {
                            if let id = library.selectedLensID {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                        .onChange(of: library.selectedLensID) { _, id in
                            // Don't move the content under a dragging finger.
                            guard let id, !isDragging else { return }
                            withAnimation(.smooth) { proxy.scrollTo(id, anchor: .center) }
                        }
                        .onChange(of: isDragging) { _, dragging in
                            guard !dragging, let id = library.selectedLensID else { return }
                            withAnimation(.smooth) { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                }
            }
        }
        .frame(height: 48)
        .clipShape(Capsule())
        .glassSurface(Capsule(), interactive: true)
        .animation(.smooth, value: library.lenses.count)
    }

    private func chips(dragsFromAnywhere: Bool) -> some View {
        let format = library.selectedFormat
        return HStack(spacing: 2) {
            ForEach(library.lenses) { lens in
                let fov = FieldOfView(focalLength: lens.focalLength, format: format)
                let isSelected = lens.id == library.selectedLensID
                chip(for: lens, isSelected: isSelected,
                     tip: HoldTip(title: lens.displayName, detail: "\(fov.anglesLabel) · \(fov.equivalentLabel)"))
                    .id(lens.id)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frame in
                        chipFrames[lens.id] = frame
                    }
            }
        }
        .padding(.horizontal, 4)
        .coordinateSpace(.named(Self.space))
        .simultaneousGesture(selectionDrag(startsAnywhere: dragsFromAnywhere))
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: library.selectedLensID)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
    }

    /// Selects the lens nearest the finger as it moves along the strip. When the strip scrolls, only a
    /// drag that starts on the selected lens selects; other drags are left to the scroll view.
    private func selectionDrag(startsAnywhere: Bool) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .updating($drag) { value, mode, _ in
                guard mode == .idle else { return }
                let onSelection = library.selectedLensID
                    .flatMap { chipFrames[$0] }
                    .map { $0.insetBy(dx: -6, dy: -6).contains(value.startLocation) } ?? false
                mode = startsAnywhere || onSelection ? .selecting : .ignoring
            }
            .onChanged { value in
                guard drag == .selecting,
                      let id = lens(nearestTo: value.location.x), id != library.selectedLensID else { return }
                library.selectedLensID = id
            }
    }

    private func lens(nearestTo x: CGFloat) -> Lens.ID? {
        library.lenses
            .compactMap { lens in chipFrames[lens.id].map { (lens.id, abs($0.midX - x)) } }
            .min { $0.1 < $1.1 }?
            .0
    }

    private func chip(for lens: Lens, isSelected: Bool, tip lensTip: HoldTip) -> some View {
        // Turned sideways, "65mm" would be taller than the chip, so only the number turns.
        let isTurned = rotation != .zero

        return HoldTipControl(tip: lensTip, shownTip: $tip) {
            library.selectedLensID = lens.id
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
            .frame(minWidth: 44)
            .frame(height: 40)
            .background {
                if isSelected {
                    SelectionThumb(isLifted: isDragging)
                        .matchedGeometryEffect(id: "thumb", in: thumbNamespace)
                }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The pill behind the selected lens. At rest it's a soft highlight; while dragging it lifts and turns
/// into clear glass.
private struct SelectionThumb: View {
    let isLifted: Bool

    var body: some View {
        Capsule()
            .fill(.white.opacity(isLifted ? 0.05 : 0.16))
            .glassLens(Capsule(), isActive: isLifted)
            .scaleEffect(isLifted ? 1.12 : 1)
    }
}
