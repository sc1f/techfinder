import SwiftUI
import TechFinderCore

/// The main screen: the live camera image with the taking frame, a status readout on top and
/// the lens bar below. Tap the image to focus and meter; pinch to show more or less of the scene
/// around the frame; press and hold a control for a tip.
struct ViewfinderView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @State private var camera = CameraController()
    @State private var orientation = DeviceOrientation()
    @State private var sheet: Sheet?
    @State private var tip: HoldTip?
    @State private var focusMarker: FocusMarker?
    @AppStorage("frameFill") private var fill = Framing.defaultFill
    @AppStorage("showsGrid") private var showsGrid = false
    @State private var pinchStartFill: Double?

    enum Sheet: String, Identifiable {
        case lenses, formats, newLens
        var id: String { rawValue }
    }

    private struct FocusMarker: Equatable {
        let id = UUID()
        let location: CGPoint
    }

    private var solution: FramingSolution? {
        guard let lens = library.selectedLens else { return nil }
        return Framing.solve(focalLength: lens.focalLength, format: library.selectedFormat,
                             optics: camera.optics, fill: fill)
    }

    var body: some View {
        let solution = self.solution
        let isSimulated = camera.status == .unavailable

        ZStack {
            Backdrop(camera: camera, zoom: solution?.zoom ?? 1)

            GeometryReader { geometry in
                let imageRect = Self.imageRect(in: geometry.size, aspectRatio: camera.optics.aspectRatio)

                ZStack {
                    imageLayer(zoom: solution?.zoom ?? 1)
                    if let solution {
                        FrameOverlay(solution: solution, showsGrid: showsGrid)
                    }
                    if let focusMarker {
                        FocusSquare()
                            .position(focusMarker.location)
                            .id(focusMarker.id)
                            .transition(.opacity)
                    }
                }
                .frame(width: imageRect.width, height: imageRect.height)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    focus(at: location, in: imageRect.size)
                }
                .position(x: imageRect.midX, y: imageRect.midY)
            }
            .ignoresSafeArea()
            .gesture(pinchToAdjustFill)

            VStack(spacing: 0) {
                topBar(solution: solution, isSimulated: isSimulated)
                    .padding(.top, 8)
                if let tip, tip.placement == .top {
                    HoldTipBubble(tip: tip)
                        .padding(.top, 12)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
                }
                Spacer()
                if let tip, tip.placement == .bottom {
                    HoldTipBubble(tip: tip)
                        .rotationEffect(orientation.rotation)
                        .padding(.bottom, orientation.isLandscape ? 60 : 12)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                }
                ControlBar(sheet: $sheet, tip: $tip, rotation: orientation.rotation)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 16)

            sideReadout(solution: solution, isSimulated: isSimulated)

            permissionMessage
        }
        .animation(.smooth(duration: 0.2), value: tip)
        .animation(.smooth, value: orientation.hold)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onChange(of: solution?.zoom ?? 1, initial: true) { _, zoom in
            camera.setZoom(zoom)
            focusMarker = nil
        }
        .task(id: tip) {
            guard tip != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            tip = nil
        }
        .task(id: focusMarker) {
            guard focusMarker != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: 0.4)) { focusMarker = nil }
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
        .sensoryFeedback(trigger: tip) { _, new in new == nil ? nil : .impact(weight: .light) }
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

    // MARK: - Top bar

    /// Lens and format buttons, with the grid toggle at the trailing edge.
    private func topBar(solution: FramingSolution?, isSimulated: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            SetupButtons(lens: library.selectedLens, format: library.selectedFormat, solution: solution,
                         isSimulated: isSimulated, sheet: $sheet, tip: $tip)
                .frame(maxWidth: .infinity)
                .opacity(orientation.isLandscape ? 0 : 1)
                .allowsHitTesting(!orientation.isLandscape)
            RoundGlassControl(systemImage: "grid", rotation: orientation.rotation,
                              tip: HoldTip(title: "Grid", detail: "Rule of thirds inside the frame · \(showsGrid ? "On" : "Off")",
                                           placement: .top),
                              shownTip: $tip, size: 46, isOn: showsGrid) {
                showsGrid.toggle()
            }
        }
    }

    /// In landscape the readout runs along whichever screen edge is currently "up" for the viewer.
    @ViewBuilder
    private func sideReadout(solution: FramingSolution?, isSimulated: Bool) -> some View {
        if orientation.isLandscape {
            GeometryReader { geometry in
                let inset: CGFloat = 12 + 22 // edge margin + half the pill's height
                let x = orientation.hold == .landscapeLeft ? geometry.size.width - inset : inset
                StatusReadout(lens: library.selectedLens, format: library.selectedFormat,
                              solution: solution, isSimulated: isSimulated)
                    .fixedSize()
                    .rotationEffect(orientation.rotation)
                    .position(x: x, y: geometry.size.height / 2)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
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

    /// Converts a tap on the upright preview into sensor coordinates and focuses and meters there.
    private func focus(at location: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        // The preview is the landscape sensor image turned 90° clockwise.
        let devicePoint = CGPoint(x: location.y / size.height, y: 1 - location.x / size.width)
        camera.focusAndMeter(at: devicePoint)
        withAnimation(.smooth(duration: 0.2)) {
            focusMarker = FocusMarker(location: location)
        }
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

/// Camera-app style focus square that settles into place where the user tapped.
private struct FocusSquare: View {
    @State private var settled = false

    var body: some View {
        Rectangle()
            .stroke(Color.accentColor, lineWidth: 1.5)
            .frame(width: 72, height: 72)
            .scaleEffect(settled ? 1 : 1.35)
            .onAppear {
                withAnimation(.smooth(duration: 0.25)) { settled = true }
            }
            .allowsHitTesting(false)
    }
}

// MARK: - Setup buttons

/// The lens and the format as two glass buttons: tap to change them, press and hold for a tip.
/// When the setup is wider than the phone can see, the lens button adds a warning line.
private struct SetupButtons: View {
    let lens: Lens?
    let format: CaptureFormat
    let solution: FramingSolution?
    let isSimulated: Bool
    @Binding var sheet: ViewfinderView.Sheet?
    @Binding var tip: HoldTip?

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            HoldTipControl(tip: HoldTip(title: "Lenses", detail: "Tap to add, edit and choose lenses", placement: .top),
                           shownTip: $tip) {
                sheet = lens == nil ? .newLens : .lenses
            } label: {
                LensReadout(lens: lens, format: format, solution: solution, isSimulated: isSimulated)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 46)
            }
            .glassSurface(RoundedRectangle(cornerRadius: 23, style: .continuous), interactive: true)

            HoldTipControl(tip: HoldTip(title: "Format", detail: "Tap to choose the back or film format", placement: .top),
                           shownTip: $tip) {
                sheet = .formats
            } label: {
                VStack(spacing: 1) {
                    Text(format.name)
                        .font(.footnote.weight(.semibold))
                    Text("Format")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(minHeight: 46)
            }
            .glassSurface(Capsule(), interactive: true)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Lens name, its angle of view on the format, and a warning when the phone can't see that wide.
private struct LensReadout: View {
    let lens: Lens?
    let format: CaptureFormat
    let solution: FramingSolution?
    let isSimulated: Bool
    /// The heading line; the landscape readout replaces it with lens and format together.
    var title: String?

    var body: some View {
        VStack(spacing: 1) {
            if let lens {
                let fov = FieldOfView(focalLength: lens.focalLength, format: format)
                Text(title ?? lens.displayName)
                    .font(.footnote.weight(.semibold))
                Text("\(fov.anglesLabel) · \(fov.equivalentLabel)\(isSimulated ? " · Simulated" : "")")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                if solution?.isClipped == true {
                    Text("Wider than the iPhone can see")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                }
            } else {
                Text("Add a lens")
                    .font(.footnote.weight(.semibold))
            }
        }
        .lineLimit(1)
        .multilineTextAlignment(.center)
        .padding(.vertical, 6)
        .contentTransition(.numericText())
        .animation(.smooth, value: lens)
        .animation(.smooth, value: format)
    }
}

/// The landscape readout along the screen edge: lens, format and angles.
private struct StatusReadout: View {
    let lens: Lens?
    let format: CaptureFormat
    let solution: FramingSolution?
    let isSimulated: Bool

    var body: some View {
        LensReadout(lens: lens, format: format, solution: solution, isSimulated: isSimulated,
                    title: lens.map { "\($0.displayName) · \(format.name)" })
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Backdrop

/// A blurred, darkened copy of the live image filling the screen behind everything, so the glass
/// controls have light and colour to refract instead of flat black.
private struct Backdrop: View {
    let camera: CameraController
    let zoom: Double

    var body: some View {
        Color.black
            .overlay {
                if camera.status == .unavailable {
                    SimulatedScene(optics: camera.optics, zoom: zoom)
                        .scaleEffect(1.7)
                        .blur(radius: 24)
                } else if let image = camera.backdrop {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                }
            }
            .overlay(Color.black.opacity(0.4))
            .clipped()
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .animation(.easeIn(duration: 0.4), value: camera.backdrop == nil)
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
