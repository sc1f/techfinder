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

        GlassGroup(spacing: 10) {
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
private struct LensStrip: View {
    @Environment(LibraryStore.self) private var library
    @Binding var sheet: ViewfinderView.Sheet?
    @Binding var tip: HoldTip?
    let rotation: Angle

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
                    chips
                        .fixedSize()
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            chips
                        }
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
                            guard let id else { return }
                            withAnimation(.smooth) { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                }
            }
        }
        .frame(height: 48)
        .clipShape(Capsule())
        .glassSurface(Capsule())
        .animation(.smooth, value: library.lenses.count)
    }

    private var chips: some View {
        let format = library.selectedFormat
        return HStack(spacing: 2) {
            ForEach(library.lenses) { lens in
                let fov = FieldOfView(focalLength: lens.focalLength, format: format)
                chip(for: lens, tip: HoldTip(title: lens.displayName, detail: "\(fov.anglesLabel) · \(fov.equivalentLabel)"))
                    .id(lens.id)
            }
        }
        .padding(.horizontal, 4)
    }

    private func chip(for lens: Lens, tip lensTip: HoldTip) -> some View {
        let isSelected = lens.id == library.selectedLensID
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
                    Capsule().fill(.white.opacity(0.14))
                }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
