import SwiftUI
import TechFinderCore

/// The main screen: the live camera image with the taking frame, the menu and setup buttons on top, and
/// the lens carousel below. Tap the image to focus and meter there; pinch to show more or less of the
/// scene around the frame; press and hold a control for a tip.
struct ViewfinderView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @State private var camera = CameraController()
    @State private var orientation = DeviceOrientation()
    /// Shown as a system sheet in portrait.
    @State private var sheet: Sheet?
    /// Shown as a rotated card in landscape, where system sheets would appear sideways.
    @State private var panel: Sheet?
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
        feedback(presentations(lifecycle(screen(solution: solution), solution: solution)))
    }

    // MARK: - Layout

    private func screen(solution: FramingSolution?) -> some View {
        let isSimulated = camera.status == .unavailable

        return ZStack {
            background(zoom: solution?.zoom ?? 1)
            viewfinder(solution: solution)
            controls(solution: solution)
            sideReadout(solution: solution, isSimulated: isSimulated)
            permissionMessage
            if let panel {
                RotatedPanel(rotation: orientation.rotation, close: closePanel) {
                    presentation(panel)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(1)
            }
        }
    }

    @ViewBuilder
    private func background(zoom: Double) -> some View {
        if LiquidGlass.isAvailable {
            Backdrop(camera: camera, zoom: zoom)
        } else {
            Color.black.ignoresSafeArea()
        }
    }

    private func viewfinder(solution: FramingSolution?) -> some View {
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
    }

    private func controls(solution: FramingSolution?) -> some View {
        VStack(spacing: 0) {
            TopBar(lens: library.selectedLens, format: library.selectedFormat, solution: solution,
                   showsSetup: !orientation.isLandscape, rotation: orientation.rotation,
                   showsGrid: $showsGrid, canResetFill: abs(fill - Framing.defaultFill) > 0.001,
                   resetFill: { withAnimation(.smooth) { fill = Framing.defaultFill } },
                   present: present, tip: $tip)
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
            ControlBar(present: present, tip: $tip, rotation: orientation.rotation)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
        .overlay(alignment: orientation.hold == .landscapeRight ? .bottomLeading : .topTrailing) {
            if orientation.isLandscape {
                // The viewer's top-left corner: the screen's top-right when the phone is turned left,
                // its bottom-left (above the lens pill) when turned right.
                MenuButton(rotation: orientation.rotation, showsGrid: $showsGrid,
                           canResetFill: abs(fill - Framing.defaultFill) > 0.001,
                           resetFill: { withAnimation(.smooth) { fill = Framing.defaultFill } })
                    .padding(.horizontal, 16)
                    .padding(orientation.hold == .landscapeRight ? .bottom : .top,
                             orientation.hold == .landscapeRight ? 8 + 48 + 16 : 8)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Behaviour

    private func lifecycle(_ content: some View, solution: FramingSolution?) -> some View {
        content
            .animation(.smooth(duration: 0.2), value: tip)
            .animation(.smooth, value: orientation.hold)
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
            .onChange(of: solution?.zoom ?? 1, initial: true) { _, zoom in
                camera.setZoom(zoom)
                // The camera returns to automatic focus for a new framing.
                focusMarker = nil
            }
            .task(id: tip) {
                guard tip != nil else { return }
                try? await Task.sleep(for: .seconds(2))
                tip = nil
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
            #if DEBUG
            // For screenshots: `-TFPresent lenses` (or formats, newLens).
            .task {
                guard let name = UserDefaults.standard.string(forKey: "TFPresent"),
                      let destination = Sheet(rawValue: name) else { return }
                try? await Task.sleep(for: .seconds(1))
                present(destination)
            }
            #endif
    }

    private func feedback(_ content: some View) -> some View {
        content
            .sensoryFeedback(.selection, trigger: library.selectedLensID)
            .sensoryFeedback(.selection, trigger: library.selectedFormatID)
            .sensoryFeedback(trigger: tip) { _, new in new == nil ? nil : .impact(weight: .light) }
            .sensoryFeedback(trigger: sheet ?? panel) { _, new in new == nil ? nil : .impact(weight: .light) }
    }

    private func presentations(_ content: some View) -> some View {
        content
            .sheet(item: $sheet) { sheet in
                presentation(sheet)
                    .presentationDetents([.medium, .large])
            }
    }

    // MARK: - Presentation

    private func present(_ destination: Sheet) {
        if orientation.isLandscape {
            withAnimation(.smooth(duration: 0.25)) { panel = destination }
        } else {
            sheet = destination
        }
    }

    private func closePanel() {
        withAnimation(.smooth(duration: 0.2)) { panel = nil }
    }

    @ViewBuilder
    private func presentation(_ destination: Sheet) -> some View {
        switch destination {
        case .lenses:
            LensLibraryView()
        case .formats:
            FormatPickerView()
        case .newLens:
            NavigationStack {
                LensEditorView(item: .new(), isRoot: true)
            }
        }
    }

    /// In landscape the readout runs along whichever screen edge is currently "up" for the viewer.
    /// Tap it to open the lenses.
    @ViewBuilder
    private func sideReadout(solution: FramingSolution?, isSimulated: Bool) -> some View {
        if orientation.isLandscape {
            GeometryReader { geometry in
                let inset: CGFloat = 12 + 24 // edge margin + half the readout's height
                let x = orientation.hold == .landscapeLeft ? geometry.size.width - inset : inset
                Button {
                    present(library.selectedLens == nil ? .newLens : .lenses)
                } label: {
                    LensReadout(lens: library.selectedLens, format: library.selectedFormat, solution: solution,
                                isSimulated: isSimulated, showsFormat: true, showsWarning: true)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                .glassSurface(RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: true)
                .fixedSize()
                .rotationEffect(orientation.rotation)
                .position(x: x, y: geometry.size.height / 2)
            }
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

    /// Moves the focus and metering point to a tap on the upright preview. Tapping the current point
    /// returns to automatic focus and exposure.
    private func focus(at location: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        if let focusMarker, hypot(focusMarker.location.x - location.x, focusMarker.location.y - location.y) < 40 {
            camera.resetFocusAndExposure()
            withAnimation(.smooth(duration: 0.2)) { self.focusMarker = nil }
            return
        }
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

/// Camera-app style focus square: settles into place where the user tapped, then dims while the point
/// stays active.
private struct FocusSquare: View {
    @State private var settled = false
    @State private var dimmed = false

    var body: some View {
        Rectangle()
            .stroke(Color.accentColor, lineWidth: 1.5)
            .frame(width: 72, height: 72)
            .scaleEffect(settled ? 1 : 1.35)
            .opacity(dimmed ? 0.45 : 1)
            .allowsHitTesting(false)
            .task {
                withAnimation(.smooth(duration: 0.25)) { settled = true }
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.easeOut(duration: 0.5)) { dimmed = true }
            }
    }
}

// MARK: - Top bar

/// The menu at the leading edge, the lens button centred on screen and the format button to its left.
/// When the setup is wider than the phone can see, a warning tag hangs under the lens button.
private struct TopBar: View {
    let lens: Lens?
    let format: CaptureFormat
    let solution: FramingSolution?
    let showsSetup: Bool
    let rotation: Angle
    @Binding var showsGrid: Bool
    let canResetFill: Bool
    let resetFill: () -> Void
    let present: (ViewfinderView.Sheet) -> Void
    @Binding var tip: HoldTip?

    private let height: CGFloat = 48

    var body: some View {
        TopBarLayout(spacing: 8) {
            MenuButton(rotation: rotation, showsGrid: $showsGrid, canResetFill: canResetFill, resetFill: resetFill)
                // In landscape the menu moves to the viewer's top-left corner instead.
                .opacity(showsSetup ? 1 : 0)
                .allowsHitTesting(showsSetup)

            HoldTipControl(tip: HoldTip(title: "Format", detail: "Tap to choose the back or film format", placement: .top),
                           shownTip: $tip) {
                present(.formats)
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
                .frame(height: height)
            }
            .glassSurface(Capsule(), interactive: true)
            .opacity(showsSetup ? 1 : 0)
            .allowsHitTesting(showsSetup)

            HoldTipControl(tip: HoldTip(title: "Lenses", detail: "Tap to add, edit and choose lenses", placement: .top),
                           shownTip: $tip) {
                present(lens == nil ? .newLens : .lenses)
            } label: {
                LensReadout(lens: lens, format: format, solution: solution, isSimulated: false,
                            showsFormat: false, showsWarning: false)
                    .padding(.horizontal, 16)
                    .frame(height: height)
            }
            .glassSurface(Capsule(), interactive: true)
            .opacity(showsSetup ? 1 : 0)
            .allowsHitTesting(showsSetup)

            if showsSetup, solution?.isClipped == true {
                Text("Wider than the iPhone can see")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .glassSurface(Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            }
        }
        .animation(.smooth, value: solution?.isClipped == true)
    }

}

/// The menu: grid and frame options now; room for the light meter and settings later.
private struct MenuButton: View {
    let rotation: Angle
    @Binding var showsGrid: Bool
    let canResetFill: Bool
    let resetFill: () -> Void

    private let size: CGFloat = 48

    var body: some View {
        Menu {
            Toggle(isOn: $showsGrid) {
                Label("Grid", systemImage: "grid")
            }
            Button(action: resetFill) {
                Label("Reset Frame Size", systemImage: "arrow.counterclockwise")
            }
            .disabled(!canResetFill)
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .rotationEffect(rotation)
                .animation(.smooth, value: rotation)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .glassSurface(Circle(), interactive: true)
        .accessibilityLabel("Menu")
    }
}

/// Places the top bar: the menu at the leading edge, the lens button centred on screen with the format
/// button beside it on the left. If the format button would run into the menu, both shift right; if
/// there still isn't room, the lens button narrows. An optional fourth view hangs centred under the lens.
private struct TopBarLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let row = subviews.prefix(3).map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        let extra = subviews.count > 3 ? spacing + subviews[3].sizeThatFits(.unspecified).height : 0
        return CGSize(width: proposal.width ?? 0, height: row + extra)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count >= 3 else { return }
        let menu = subviews[0].sizeThatFits(.unspecified)
        let format = subviews[1].sizeThatFits(.unspecified)
        let lensIdeal = subviews[2].sizeThatFits(.unspecified)
        let row = max(menu.height, format.height, lensIdeal.height)
        let midY = bounds.minY + row / 2

        subviews[0].place(at: CGPoint(x: bounds.minX, y: midY), anchor: .leading, proposal: ProposedViewSize(menu))

        let earliestLens = bounds.minX + menu.width + spacing + format.width + spacing
        let lensWidth = min(lensIdeal.width, bounds.maxX - earliestLens)
        let lensX = min(max(bounds.midX - lensWidth / 2, earliestLens), bounds.maxX - lensWidth)
        subviews[2].place(at: CGPoint(x: lensX, y: midY), anchor: .leading,
                          proposal: ProposedViewSize(width: lensWidth, height: lensIdeal.height))
        subviews[1].place(at: CGPoint(x: lensX - spacing - format.width, y: midY), anchor: .leading,
                          proposal: ProposedViewSize(format))

        if subviews.count > 3 {
            let tag = subviews[3].sizeThatFits(.unspecified)
            subviews[3].place(at: CGPoint(x: lensX + lensWidth / 2, y: bounds.minY + row + spacing), anchor: .top,
                              proposal: ProposedViewSize(tag))
        }
    }
}

/// Lens name (optionally with the format), its angle of view on the format and, optionally, a warning
/// when the phone can't see that wide.
private struct LensReadout: View {
    let lens: Lens?
    let format: CaptureFormat
    let solution: FramingSolution?
    let isSimulated: Bool
    let showsFormat: Bool
    let showsWarning: Bool

    var body: some View {
        VStack(spacing: 1) {
            if let lens {
                let fov = FieldOfView(focalLength: lens.focalLength, format: format)
                Text(showsFormat ? "\(lens.displayName) · \(format.name)" : lens.displayName)
                    .font(.footnote.weight(.semibold))
                Text("\(fov.anglesLabel) · \(fov.equivalentLabel)\(isSimulated ? " · Simulated" : "")")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                if showsWarning, solution?.isClipped == true {
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

// MARK: - Backdrop

/// A softly blurred, darkened copy of the live image filling the screen behind everything, so the
/// Liquid Glass controls have light and colour to refract. Frames crossfade so it drifts rather than
/// steps.
private struct Backdrop: View {
    let camera: CameraController
    let zoom: Double

    var body: some View {
        Color.black
            .overlay {
                if camera.status == .unavailable {
                    SimulatedScene(optics: camera.optics, zoom: zoom)
                        .scaleEffect(1.7)
                        .blur(radius: 30)
                } else if let image = camera.backdrop {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 12)
                        .scaleEffect(1.15)
                        .id(ObjectIdentifier(image))
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: camera.backdrop.map(ObjectIdentifier.init))
            .overlay(Color.black.opacity(0.35))
            .clipped()
            .ignoresSafeArea()
            .allowsHitTesting(false)
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
