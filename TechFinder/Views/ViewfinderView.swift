import SwiftUI
import TechFinderCore

/// The main screen: the live camera image with the taking frame, a status readout on top and
/// the lens bar below. Pinch to show more or less of the scene around the frame; double-tap to reset.
struct ViewfinderView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @State private var camera = CameraController()
    @State private var orientation = DeviceOrientation()
    @State private var sheet: Sheet?
    @AppStorage("frameFill") private var fill = Framing.defaultFill
    @State private var pinchStartFill: Double?

    enum Sheet: String, Identifiable {
        case lenses, formats, newLens
        var id: String { rawValue }
    }

    private var solution: FramingSolution? {
        guard let lens = library.selectedLens else { return nil }
        return Framing.solve(focalLength: lens.focalLength, format: library.selectedFormat,
                             optics: camera.optics, fill: fill)
    }

    var body: some View {
        let solution = self.solution

        ZStack {
            GeometryReader { geometry in
                let imageRect = Self.imageRect(in: geometry.size, aspectRatio: camera.optics.aspectRatio)

                ZStack {
                    imageLayer(zoom: solution?.zoom ?? 1)
                    if let solution {
                        FrameOverlay(solution: solution)
                    }
                }
                .frame(width: imageRect.width, height: imageRect.height)
                .position(x: imageRect.midX, y: imageRect.midY)
            }
            .background(.black)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .gesture(pinchToAdjustFill)
            .onTapGesture(count: 2) {
                withAnimation(.smooth) { fill = Framing.defaultFill }
            }

            VStack(spacing: 0) {
                StatusReadout(lens: library.selectedLens, format: library.selectedFormat,
                              solution: solution, isSimulated: camera.status == .unavailable)
                    .padding(.top, 8)
                Spacer()
                ControlBar(sheet: $sheet, iconRotation: orientation.iconRotation)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 16)

            permissionMessage
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onChange(of: solution?.zoom ?? 1, initial: true) { _, zoom in
            camera.setZoom(zoom)
        }
        .task {
            await camera.start()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                UIApplication.shared.isIdleTimerDisabled = true
                Task { await camera.start() }
            case .background:
                UIApplication.shared.isIdleTimerDisabled = false
                camera.stop()
            default:
                break
            }
        }
        .onAppear {
            // Scouting takes time; keep the screen on while framing.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .sensoryFeedback(.selection, trigger: library.selectedLensID)
        .sensoryFeedback(.selection, trigger: library.selectedFormatID)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .lenses:
                LensLibraryView()
                    .presentationDetents([.medium, .large])
            case .formats:
                FormatPickerView()
                    .presentationDetents([.medium, .large])
            case .newLens:
                LensEditorView(item: .new())
            }
        }
    }

    // MARK: - Camera image

    @ViewBuilder
    private func imageLayer(zoom: Double) -> some View {
        switch camera.status {
        case .unavailable:
            SimulatedScene(optics: camera.optics, zoom: zoom)
        default:
            CameraPreview(session: camera.session, isRunning: camera.status == .running)
        }
    }

    /// The camera image, upright and fitted to the screen width without cropping, centred vertically.
    static func imageRect(in container: CGSize, aspectRatio: Double) -> CGRect {
        guard container.width > 0, container.height > 0 else { return .zero }
        let portraitAspect = 1 / aspectRatio // width / height
        var size = CGSize(width: container.width, height: container.width / portraitAspect)
        if size.height > container.height {
            size = CGSize(width: container.height * portraitAspect, height: container.height)
        }
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    private var pinchToAdjustFill: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStartFill ?? fill
                pinchStartFill = start
                fill = min(max(start * value.magnification, Framing.fillRange.lowerBound), Framing.fillRange.upperBound)
            }
            .onEnded { _ in
                pinchStartFill = nil
            }
    }

    // MARK: - Permission

    @ViewBuilder
    private var permissionMessage: some View {
        switch camera.status {
        case .unauthorized:
            MessageCard(title: "Camera Access Needed",
                        message: "TechFinder shows your composition through the iPhone camera. Allow camera access in Settings.",
                        actionTitle: "Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        case .failed(let reason):
            MessageCard(title: "Camera Unavailable", message: reason, actionTitle: nil, action: {})
        default:
            EmptyView()
        }
    }
}

// MARK: - Status readout

/// Discreet glass pill: lens and format, and the angle of view the frame represents.
private struct StatusReadout: View {
    let lens: Lens?
    let format: CaptureFormat
    let solution: FramingSolution?
    let isSimulated: Bool

    var body: some View {
        VStack(spacing: 2) {
            if let lens {
                let fov = FieldOfView(focalLength: lens.focalLength, format: format)
                Text("\(lens.displayName) · \(format.name)")
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Group {
                    if solution?.isClipped == true {
                        Text("Wider than the iPhone can see · \(fov.anglesLabel)")
                            .foregroundStyle(.orange)
                    } else {
                        Text("\(fov.anglesLabel) · \(fov.equivalentLabel)\(isSimulated ? " · Simulated" : "")")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption2.monospacedDigit())
                .lineLimit(1)
            } else {
                Text("Add a lens to start framing")
                    .font(.footnote.weight(.semibold))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .glassSurface(Capsule())
        .contentTransition(.numericText())
        .animation(.smooth, value: lens)
        .animation(.smooth, value: format)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Messages

private struct MessageCard: View {
    let title: String
    let message: String
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.aperture")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassSurface(Capsule(), interactive: true)
            }
        }
        .padding(24)
        .frame(maxWidth: 320)
        .glassSurface(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
