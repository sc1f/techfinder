import SwiftUI
import TechFinderCore

/// The main screen: the live camera image with the taking frame, the menu and setup buttons on top, and
/// the lens carousel below. Tap the image to focus and meter there; pinch to show more or less of the
/// scene around the frame.
struct ViewfinderView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @State private var camera = CameraController()
    @State private var orientation = DeviceOrientation()
    /// Shown as a system sheet in portrait.
    @State private var sheet: Sheet?
    /// Shown as a rotated card in landscape, where system sheets would appear sideways.
    @State private var panel: Sheet?
    @State private var focusMarker: FocusMarker?
    /// Exposure compensation in stops for the current focus point, set by dragging after a tap.
    @State private var exposureBias: Float = 0
    @State private var exposureDragStart: Float?
    /// Bumped by every touch on the image; the focus square hides after 3 s without one.
    @State private var focusActivity = 0
    @AppStorage("frameFill") private var fill = Framing.defaultFill
    @AppStorage("showsGrid") private var showsGrid = false
    @State private var pinchStartFill: Double?
    @State private var movements = MovementState()
    @State private var movementDragStart: Movement?
    /// Bumped when a movement stops at the image circle or the camera's limit.
    @State private var movementStops = 0

    enum Sheet: String, Identifiable {
        case lenses, formats, newLens, settings
        var id: String { rawValue }
    }

    private struct FocusMarker: Equatable {
        let id = UUID()
        let location: CGPoint
    }

    /// The one animation for everything that moves when the phone turns.
    static let turn = Animation.spring(response: 0.42, dampingFraction: 0.86)

    private var solution: FramingSolution? {
        guard let lens = library.selectedLens else { return nil }
        return Framing.solve(focalLength: lens.focalLength, format: library.selectedFormat,
                             optics: camera.optics, fill: fill)
    }

    /// Movements for the current lens, format, aperture and hold, when movements are on.
    struct MovementInfo {
        var layout: MovementLayout
        var geometry: MovementGeometry
        var imageCircle: ImageCircleModel.Estimate?
        var focalLength: Double
        /// Room between the furthest corner and the image circle edge, in mm.
        var margin: Double? { imageCircle.map { geometry.margin(movement, imageCircle: $0.diameter) } }
        var movement: Movement
    }

    var body: some View {
        let solution = self.solution
        let exposure = ExposureSolver.solve(library.exposure, meteredEV100: camera.meteredEV,
                                            compensation: Double(exposureBias))
        let movement = movementInfo(exposure: exposure)
        let zoom = movement?.layout.zoom ?? solution?.zoom ?? 1
        feedback(presentations(simulation(lifecycle(screen(solution: solution, exposure: exposure, movement: movement),
                                                    zoom: zoom),
                                          exposure: exposure)))
    }

    private func movementInfo(exposure: ExposureSolution) -> MovementInfo? {
        guard movements.isOn, let lens = library.selectedLens else { return nil }
        let imageCircle = lens.imageCircle(at: ExposureScale.aperture(exposure.apertureIndex))
        let geometry = MovementGeometry(format: library.selectedFormat, riseAlongLongSide: !orientation.isLandscape)
        let layout = MovementPlanner.layout(format: library.selectedFormat, focalLength: lens.focalLength,
                                            movement: movements.movement, imageCircle: imageCircle?.diameter,
                                            limits: library.movementLimits, turnedLeft: turnedLeft,
                                            optics: camera.optics)
        return MovementInfo(layout: layout, geometry: geometry, imageCircle: imageCircle,
                            focalLength: lens.focalLength, movement: movements.movement)
    }

    /// Nil when upright; whether the phone's top points left when sideways.
    private var turnedLeft: Bool? {
        switch orientation.hold {
        case .portrait: nil
        case .landscapeLeft: true
        case .landscapeRight: false
        }
    }

    private var exposureSettings: Binding<ExposureSettings> {
        Binding(get: { library.exposure }, set: { library.exposure = $0 })
    }

    // MARK: - Layout

    private func screen(solution: FramingSolution?, exposure: ExposureSolution, movement: MovementInfo?) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            viewfinder(solution: solution, movement: movement)
            controls(solution: solution, exposure: exposure, movement: movement)
            sideBlocks(solution: solution, exposure: exposure, movement: movement)
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


    private func viewfinder(solution: FramingSolution?, movement: MovementInfo?) -> some View {
        GeometryReader { geometry in
            let imageRect = Self.imageRect(in: geometry.size, aspectRatio: camera.optics.aspectRatio)
            let mapping = movement.map {
                MovementMapping.make(layout: $0.layout, imageSize: imageRect.size, showsOverview: movements.showsOverview)
            }
            let transform = movement.flatMap { info in
                mapping.map { $0.imageTransform(layout: info.layout, imageSize: imageRect.size) }
            } ?? (scale: 1, offset: .zero)

            ZStack {
                // One camera image throughout; in movement mode it is magnified and panned to the moved frame.
                imageLayer(zoom: movement?.layout.zoom ?? solution?.zoom ?? 1)
                    .scaleEffect(transform.scale)
                    .offset(transform.offset)
                if let movement, let mapping {
                    MovementOverlay(layout: movement.layout, mapping: mapping, margin: movement.margin,
                                    showsGrid: showsGrid)
                } else if let solution {
                    FrameOverlay(solution: solution, showsGrid: showsGrid)
                }
                if let focusMarker {
                    FocusSquare(exposureBias: exposureBias, isAdjusting: exposureDragStart != nil)
                        .position(focusMarker.location)
                        .id(focusMarker.id)
                        .transition(.opacity)
                }
            }
            .frame(width: imageRect.width, height: imageRect.height)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { location in
                focus(at: location, in: imageRect.size, transform: transform)
            }
            .gesture(imageDrag(movement: movement, mapping: mapping))
            .position(x: imageRect.midX, y: imageRect.midY)
        }
        .ignoresSafeArea()
        .gesture(pinchToAdjustFill)
    }

    private func controls(solution: FramingSolution?, exposure: ExposureSolution, movement: MovementInfo?) -> some View {
        VStack(spacing: 0) {
            topBlock(exposure: exposure, rotation: orientation.rotation)
                .padding(.top, 8)
                .opacity(orientation.isLandscape ? 0 : 1)
                .allowsHitTesting(!orientation.isLandscape)
            Spacer()
            setupBlock(solution: solution, movement: movement)
                .padding(.bottom, 12)
                .opacity(orientation.isLandscape ? 0 : 1)
                .allowsHitTesting(!orientation.isLandscape)
            ControlBar(present: present, rotation: orientation.rotation)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
    }

    /// The light meter with the tools under it. In landscape the whole block is turned, so its icons
    /// don't turn on their own (`rotation` is zero there).
    private func topBlock(exposure: ExposureSolution, rotation: Angle) -> some View {
        VStack(spacing: 8) {
            MeterBar(settings: exposureSettings, solution: exposure, limits: library.exposureLimits,
                     hasReading: camera.meteredEV != nil)
            ToolRow(rotation: rotation, showsGrid: $showsGrid, showsMovements: movementsToggle,
                    canResetFill: abs(fill - Framing.defaultFill) > 0.001,
                    resetFill: { withAnimation(.smooth) { fill = Framing.defaultFill } },
                    openSettings: { present(.settings) })
        }
    }

    /// The lens and format pills, with the warning above them when the setup is too wide. With movements
    /// on, the movement controls take their place.
    @ViewBuilder
    private func setupBlock(solution: FramingSolution?, movement: MovementInfo?) -> some View {
        if let movement {
            MovementBar(state: $movements, margin: movement.margin,
                        imageCircleIsEstimate: movement.imageCircle?.isEstimate == true) { delta in
                move(movements.axis, to: movements.movement[movements.axis] + delta, info: movement)
            }
            .transition(.opacity)
        } else {
            SetupBar(lens: library.selectedLens, format: library.selectedFormat,
                     isClipped: solution?.isClipped == true, isSimulated: camera.status == .unavailable,
                     present: present)
            .transition(.opacity)
        }
    }

    private var movementsToggle: Binding<Bool> {
        Binding(get: { movements.isOn }, set: { isOn in
            withAnimation(.smooth(duration: 0.35)) { movements.isOn = isOn }
        })
    }

    /// Moves one axis, stopping at the image circle and the camera's limits, in half-millimetre steps.
    private func move(_ axis: MovementAxis, to value: Double, info: MovementInfo) {
        let snapped = (value * 2).rounded() / 2
        let moved = info.geometry.moving(movements.movement, axis, to: snapped,
                                         imageCircle: info.imageCircle?.diameter, limits: library.movementLimits,
                                         increment: 0.5)
        if abs(moved[axis] - snapped) > 1e-9, moved[axis] == movements.movement[axis] {
            movementStops += 1
        }
        movements.movement = moved
    }

    // MARK: - Behaviour

    private func lifecycle(_ content: some View, zoom: Double) -> some View {
        content
            .animation(Self.turn, value: orientation.hold)
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
            .onChange(of: zoom, initial: true) { _, zoom in
                camera.setZoom(zoom)
                // The camera returns to automatic focus and exposure for a new framing.
                focusMarker = nil
                exposureBias = 0
            }
            .task(id: focusActivity) {
                // Hide the focus square after 3 s without a touch; the point stays active.
                guard focusMarker != nil else { return }
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, exposureDragStart == nil else { return }
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
            #if DEBUG
            // For screenshots: `-TFImageCircle 90` gives the selected lens a 90 mm image circle at f/11;
            // `-TFMovements YES -TFRise 10 -TFShift 5 -TFOverview YES` opens movements.
            .task {
                let defaults = UserDefaults.standard
                if defaults.double(forKey: "TFImageCircle") > 0, var lens = library.selectedLens {
                    lens.imageCircle = [ImageCirclePoint(diameter: defaults.double(forKey: "TFImageCircle"), fNumber: 11)]
                    library.save(lens)
                }
                if defaults.bool(forKey: "TFMovements") {
                    movements.isOn = true
                    movements.movement = Movement(rise: defaults.double(forKey: "TFRise"), shift: defaults.double(forKey: "TFShift"))
                    movements.showsOverview = defaults.bool(forKey: "TFOverview")
                }
            }
            // For screenshots: `-TFPresent lenses` (or formats, newLens).
            .task {
                guard let name = UserDefaults.standard.string(forKey: "TFPresent"),
                      let destination = Sheet(rawValue: name) else { return }
                try? await Task.sleep(for: .seconds(1))
                present(destination)
            }
            #endif
    }

    /// Shows the chosen exposure in the viewfinder: the preview is brightened or darkened by however
    /// many stops the settings are over- or underexposed.
    private func simulation(_ content: some View, exposure: ExposureSolution) -> some View {
        content
            .onChange(of: exposure.exposureError, initial: true) { _, error in
                camera.setExposureBias(Float(error))
            }
    }

    private func feedback(_ content: some View) -> some View {
        content
            .sensoryFeedback(.selection, trigger: library.selectedLensID)
            // A tick for each whole millimetre of movement, and a firm stop at the image circle or limit.
            .sensoryFeedback(.selection, trigger: Int(movements.movement.rise.rounded(.towardZero)) * 1000
                                                  + Int(movements.movement.shift.rounded(.towardZero)))
            .sensoryFeedback(.impact(weight: .heavy), trigger: movementStops)
            .sensoryFeedback(.selection, trigger: library.selectedFormatID)
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
        case .settings:
            ExposureSettingsView()
        }
    }

    /// In landscape the meter and tools run along the viewer's top edge and the lens and format pills
    /// along the viewer's bottom edge, each turned to read along it.
    @ViewBuilder
    private func sideBlocks(solution: FramingSolution?, exposure: ExposureSolution, movement: MovementInfo?) -> some View {
        if orientation.isLandscape {
            let isClipped = solution?.isClipped == true
            let pill = GlassButtonMetrics.pillHeight
            GeometryReader { geometry in
                // Distance from each screen edge to the centre of its turned block.
                let topInset = 12 + (pill * 2 + 8) / 2
                let bottomInset = 12 + (pill + (isClipped ? 8 + WarningTag.height : 0)) / 2
                let turnedLeft = orientation.hold == .landscapeLeft

                topBlock(exposure: exposure, rotation: .zero)
                    .frame(width: 340)
                    .fixedSize()
                    .rotationEffect(orientation.rotation)
                    .position(x: turnedLeft ? geometry.size.width - topInset : topInset, y: geometry.size.height / 2)

                setupBlock(solution: solution, movement: movement)
                    .fixedSize()
                    .rotationEffect(orientation.rotation)
                    .position(x: turnedLeft ? bottomInset : geometry.size.width - bottomInset,
                              y: geometry.size.height / 2)
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
    private func focus(at location: CGPoint, in size: CGSize, transform: (scale: CGFloat, offset: CGSize)) {
        guard size.width > 0, size.height > 0 else { return }
        if let focusMarker, hypot(focusMarker.location.x - location.x, focusMarker.location.y - location.y) < 40 {
            camera.resetFocusAndExposure()
            exposureBias = 0
            withAnimation(.smooth(duration: 0.2)) { self.focusMarker = nil }
            return
        }
        exposureBias = 0
        focusActivity += 1
        // Undo the movement view's magnification to find the point on the camera image.
        let image = CGPoint(x: size.width / 2 + (location.x - size.width / 2 - transform.offset.width) / transform.scale,
                            y: size.height / 2 + (location.y - size.height / 2 - transform.offset.height) / transform.scale)
        // The preview is the landscape sensor image turned 90° clockwise.
        let devicePoint = CGPoint(x: min(max(image.y / size.height, 0), 1), y: min(max(1 - image.x / size.width, 0), 1))
        camera.focusAndMeter(at: devicePoint)
        withAnimation(.smooth(duration: 0.2)) {
            focusMarker = FocusMarker(location: location)
        }
    }

    /// Dragging on the image. With movements on, it moves the chosen axis only: in the overview the frame
    /// follows the finger; in the result view the scene does, like panning a photo. Otherwise, after a
    /// tap, dragging up brightens and down darkens, about one stop per 100 points, within ±2 stops.
    private func imageDrag(movement: MovementInfo?, mapping: MovementMapping?) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if let movement, let mapping {
                    let start = movementDragStart ?? movements.movement
                    movementDragStart = start
                    let directions = MovementPlanner.screenDirections(sideways: turnedLeft)
                    let direction = movements.axis == .rise ? directions.rise : directions.shift
                    let along = Double(value.translation.width) * direction.x + Double(value.translation.height) * direction.y
                    let millimetres = (movements.showsOverview ? 1 : -1) * along / mapping.pointsPerTan * movement.focalLength
                    move(movements.axis, to: start[movements.axis] + millimetres, info: movement)
                } else {
                    guard focusMarker != nil else { return }
                    let start = exposureDragStart ?? exposureBias
                    exposureDragStart = start
                    exposureBias = min(max(start - Float(value.translation.height / 100), -2), 2)
                }
            }
            .onEnded { _ in
                if movementDragStart != nil {
                    movementDragStart = nil
                } else {
                    exposureDragStart = nil
                    focusActivity += 1
                }
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

/// Camera-app style focus square: settles into place where the user tapped. A sun beside it shows
/// exposure compensation, moving up as the image brightens. The viewfinder hides it after 3 s idle.
private struct FocusSquare: View {
    let exposureBias: Float
    let isAdjusting: Bool

    @State private var settled = false

    var body: some View {
        Rectangle()
            .stroke(Color.accentColor, lineWidth: 1.5)
            .frame(width: 72, height: 72)
            .overlay(alignment: .trailing) {
                VStack(spacing: 2) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 13, weight: .semibold))
                    if isAdjusting || exposureBias != 0 {
                        Text(String(format: "%+.1f", exposureBias))
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    }
                }
                .foregroundStyle(Color.accentColor)
                .offset(x: 26, y: CGFloat(-exposureBias) * 18)
            }
            .scaleEffect(settled ? 1 : 1.35)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.smooth(duration: 0.25)) { settled = true }
            }
    }
}

// MARK: - Top bar

/// The lens and format pills, centred. When the setup is wider than the phone can see, a warning tag
/// sits above them.
private struct SetupBar: View {
    let lens: Lens?
    let format: CaptureFormat
    let isClipped: Bool
    let isSimulated: Bool
    let present: (ViewfinderView.Sheet) -> Void

    var body: some View {
        VStack(spacing: 8) {
            if isClipped {
                WarningTag()
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
            }
            HStack(spacing: 8) {
                LensPillButton(lens: lens, format: format, isSimulated: isSimulated) {
                    present(lens == nil ? .newLens : .lenses)
                }
                FormatPillButton(format: format) {
                    present(.formats)
                }
                .fixedSize()
            }
        }
        .animation(.smooth, value: isClipped)
    }
}

// MARK: - Tools

/// Tools under the light meter, centred: grid, reset frame size, movements and settings.
private struct ToolRow: View {
    let rotation: Angle
    @Binding var showsGrid: Bool
    @Binding var showsMovements: Bool
    let canResetFill: Bool
    let resetFill: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ToolButton(systemImage: "grid", label: "Grid", isOn: showsGrid, rotation: rotation) {
                showsGrid.toggle()
            }
            .accessibilityIdentifier("gridButton")
            ToolButton(systemImage: "arrow.counterclockwise", label: "Reset Frame Size", rotation: rotation) {
                resetFill()
            }
            .disabled(!canResetFill)
            .accessibilityIdentifier("resetFrameButton")
            ToolButton(systemImage: "arrow.up.and.down.and.arrow.left.and.right", label: "Movements",
                       isOn: showsMovements, rotation: rotation) {
                showsMovements.toggle()
            }
            .accessibilityIdentifier("movementsButton")
            ToolButton(systemImage: "slider.horizontal.3", label: "Settings", rotation: rotation) {
                openSettings()
            }
            .accessibilityIdentifier("settingsButton")
        }
    }
}

/// A glass pill with an icon that turns with the phone, and a firm haptic when pressed.
private struct ToolButton: View {
    let systemImage: String
    let label: String
    var isOn = false
    let rotation: Angle
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var presses = 0

    private static let width: CGFloat = 64

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
                .frame(width: Self.width - GlassButtonMetrics.padding.leading - GlassButtonMetrics.padding.trailing,
                       height: GlassButtonMetrics.pillLabelHeight)
        }
        .glassButtonStyle(Capsule())
        .sensoryFeedback(.impact(weight: .medium, intensity: 1), trigger: presses)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The lens name and its angle of view on the format, as a glass pill button. Opens the lenses.
private struct LensPillButton: View {
    let lens: Lens?
    let format: CaptureFormat
    let isSimulated: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LensReadout(lens: lens, format: format, isSimulated: isSimulated)
                .padding(.horizontal, 4)
                .frame(height: GlassButtonMetrics.pillLabelHeight)
        }
        .glassButtonStyle(Capsule())
        .accessibilityHint("Add, edit and choose lenses")
        .accessibilityIdentifier("lensButton")
    }
}

/// The format name as a glass pill button. Opens the format picker.
private struct FormatPillButton: View {
    let format: CaptureFormat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(format.name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .frame(height: GlassButtonMetrics.pillLabelHeight)
        }
        .glassButtonStyle(Capsule())
        .accessibilityLabel("Format, \(format.name)")
        .accessibilityIdentifier("formatButton")
    }
}

/// Shown under the lens pill when the setup is wider than the phone's camera can see.
private struct WarningTag: View {
    static let height: CGFloat = 22

    var body: some View {
        Text("Wider than the iPhone can see")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 12)
            .frame(height: Self.height)
            .glassSurface(Capsule())
    }
}

/// Lens name and its angle of view on the format.
private struct LensReadout: View {
    let lens: Lens?
    let format: CaptureFormat
    let isSimulated: Bool

    var body: some View {
        VStack(spacing: 1) {
            if let lens {
                let fov = FieldOfView(focalLength: lens.focalLength, format: format)
                Text(lens.displayName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                Text("\(fov.anglesLabel) · \(fov.equivalentLabel)\(isSimulated ? " · Simulated" : "")")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("Add a lens")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .lineLimit(1)
        .multilineTextAlignment(.center)
        .contentTransition(.numericText())
        .animation(.smooth, value: lens)
        .animation(.smooth, value: format)
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
