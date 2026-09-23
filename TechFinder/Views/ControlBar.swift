import SwiftUI
import TechFinderCore

/// Bottom controls: format, the lens strip for one-tap lens changes, and the lens library.
struct ControlBar: View {
    @Binding var sheet: ViewfinderView.Sheet?
    let iconRotation: Angle

    var body: some View {
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                RoundGlassButton(systemImage: "rectangle.dashed", label: "Format", rotation: iconRotation) {
                    sheet = .formats
                }
                LensStrip(sheet: $sheet)
                RoundGlassButton(systemImage: "camera.aperture", label: "Lenses", rotation: iconRotation) {
                    sheet = .lenses
                }
            }
        }
    }
}

private struct RoundGlassButton: View {
    let systemImage: String
    let label: String
    let rotation: Angle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .rotationEffect(rotation)
                .animation(.smooth, value: rotation)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .glassSurface(Circle(), interactive: true)
        .accessibilityLabel(label)
    }
}

/// Horizontal strip of saved lenses, labelled by focal length, wide to long.
private struct LensStrip: View {
    @Environment(LibraryStore.self) private var library
    @Binding var sheet: ViewfinderView.Sheet?

    var body: some View {
        Group {
            if library.lenses.isEmpty {
                Button {
                    sheet = .newLens
                } label: {
                    Label("Add Lens", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(library.lenses) { lens in
                                chip(for: lens)
                                    .id(lens.id)
                            }
                        }
                        .padding(.horizontal, 4)
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
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .clipShape(Capsule())
        .glassSurface(Capsule())
    }

    private func chip(for lens: Lens) -> some View {
        let isSelected = lens.id == library.selectedLensID

        return Button {
            library.selectedLensID = lens.id
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(lens.focalLengthLabel)
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                Text("mm")
                    .font(.system(size: 10, weight: .medium))
                    .opacity(0.7)
            }
            .foregroundStyle(isSelected ? Color.accentColor : .white)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background {
                if isSelected {
                    Capsule().fill(.white.opacity(0.14))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lens.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Text(lens.displayName)
            Button("Edit Lenses", systemImage: "slider.horizontal.3") { sheet = .lenses }
        }
    }
}
