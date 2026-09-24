import SwiftUI
import TechFinderCore

/// The main screen: the live camera image with the taking frame, the menu and setup buttons on top, and
/// the lens selector below. Pinch to show more or less of the scene around the frame; with movements on,
/// drag to move and double-tap to return the current movement to zero.
struct ViewfinderView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @State private var camera = CameraController()
    @State private var orientation = DeviceOrientation()
    /// Shown as a system sheet in portrait.
    @State private var sheet: Sheet?
    /// Shown as a rotated card in landscape, where system sheets would appear sideways.
    @State private var panel: Sheet?
    @AppStorage("frameFill") private var fill = Framing.defaultFill
    @AppStorage("showsGrid") private var showsGrid = false
    @State private var pinchStartFill: Double?
    @State private var movements = MovementState()
    @State private var movementDragStart: Movement?
    /// Bumped when a movement stops at the image circle or the camera's limit.
    @State private var movementStops = 0
    /// The screen's safe area. Full-screen layers ignore it, so it is read from the screen's own frame.
    @State private var safeArea = EdgeInsets()
    /// A movement a double-tap just returned to zero, which the banner offers to put back.
    @State private var undoableReset: (axis: MovementAxis, value: Double, id: UUID)?
    /// The lens nickname shown briefly over the image after choosing a lens.
    @State private var lensNotice: (name: String, id: UUID)?
    @AppStorage("hasSeenSpotHint") private var hasSeenSpotHint = false
    @State private var showsSpotHint = false

    enum Sheet: String, Identifiable {
        case lenses, formats, newLens, settings
        var id: String { rawValue }
    }

    /// The spot meter's angle of view.
    static let spotAngle = 3.0

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
        /// The quoted aperture of the image circle figure in use.
        var aperture: Double
        var focalLength: Double
        /// Room between the furthest corner and the image circle edge, in mm.
        var margin: Double? { imageCircle.map { geometry.margin(movement, imageCircle: $0.diameter) } }
        var movement: Movement
    }

    var body: some View {
        let solution = self.solution
        let exposure = ExposureSolver.solve(library.exposure, meteredEV100: meteredEV)
        let movement = movementInfo(exposure: exposure)
        let zoom = movement?.layout.zoom ?? solution?.zoom ?? 1
        feedback(presentations(lifecycle(screen(solution: solution, exposure: exposure, movement: movement),
                                         zoom: zoom)))
    }

    private func movementInfo(exposure: ExposureSolution) -> MovementInfo? {
        guard movements.isOn, let lens = library.selectedLens else { return nil }
        // Use the lens's quoted figure at the aperture closest to the meter's.
        let figure = ImageCircleModel.nearest(lens.imageCircle, to: ExposureScale.aperture(exposure.apertureIndex))
        let imageCircle = figure.map { ImageCircleModel.Estimate(diameter: $0.diameter, isEstimate: false) }
        let aperture = figure?.fNumber ?? ExposureScale.aperture(exposure.apertureIndex)
        let geometry = MovementGeometry(format: library.selectedFormat, riseAlongLongSide: !orientation.isLandscape)
        let layout = MovementPlanner.layout(format: library.selectedFormat, focalLength: lens.focalLength,
                                            movement: movements.movement, imageCircle: imageCircle?.diameter,
                                            limits: library.movementLimits, turnedLeft: turnedLeft,
                                            optics: camera.optics)
        return MovementInfo(layout: layout, geometry: geometry, imageCircle: imageCircle, aperture: aperture,
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

    /// The spot meter's reading with the user's calibration applied.
    private var meteredEV: Double? {
        camera.meteredEV.map { $0 + library.meterCalibration }
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
        .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { safeArea = $0 }
    }


    private func viewfinder(solution: FramingSolution?, movement: MovementInfo?) -> some View {
        GeometryReader { geometry in
            let imageRect = screenLayout(geometry, solution: solution, movement: movement).image
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
                let spot = spotPlacement(imageSize: imageRect.size, zoom: movement?.layout.zoom ?? solution?.zoom ?? 1,
                                         movement: movement, mapping: mapping)
                Circle()
                    .stroke(.white.opacity(0.85), lineWidth: 1)
                    .frame(width: spot.radius * 2, height: spot.radius * 2)
                    .position(spot.location)
                    .allowsHitTesting(false)
                    .onChange(of: spot.region, initial: true) { _, region in
                        camera.setSpot(region)
                    }
                if showsSpotHint {
                    // Below the circle as the viewer holds the phone.
                    let angle = orientation.rotation.radians
                    let distance = spot.radius + 16
                    Text("Spot meter")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .glassSurface(Capsule())
                        .rotationEffect(orientation.rotation)
                        .position(x: spot.location.x - sin(angle) * distance, y: spot.location.y + cos(angle) * distance)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .frame(width: imageRect.width, height: imageRect.height)
            .clipped()
            .contentShape(Rectangle())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("viewfinderImage")
            .onTapGesture(count: 2) {
                guard let movement else { return }
                let axis = movements.axis
                let previous = movements.movement[axis]
                guard previous != 0 else { return }
                move(axis, to: 0, info: movement)
                withAnimation(.smooth(duration: 0.25)) { undoableReset = (axis, previous, UUID()) }
            }
            .gesture(imageDrag(movement: movement, mapping: mapping))
            .position(x: imageRect.midX, y: imageRect.midY)

            // Over the image but outside its gestures, so the buttons are hit and reported where they are.
            ImageNotices(rotation: orientation.rotation, size: imageRect.size,
                         lensName: lensNotice?.name, undo: undoText,
                         performUndo: performUndo,
                         zoom: abs(fill - Framing.defaultFill) > 0.001 ? fill / Framing.defaultFill : nil,
                         resetZoom: { withAnimation(.smooth) { fill = Framing.defaultFill } })
                .position(x: imageRect.midX, y: imageRect.midY)
        }
        .ignoresSafeArea()
        .gesture(pinchToAdjustFill)
    }

    private var undoText: String? {
        undoableReset.map { "\($0.axis == .rise ? "Rise" : "Shift") reset to 0" }
    }

    private func performUndo() {
        guard let reset = undoableReset, let movement = movementInfo(exposure: ExposureSolver.solve(library.exposure, meteredEV100: meteredEV)) else { return }
        movements.axis = reset.axis
        move(reset.axis, to: reset.value, info: movement)
        withAnimation(.smooth(duration: 0.2)) { undoableReset = nil }
    }

    /// Everything sits below the camera image, within thumb reach, sharing out the band evenly: the
    /// movement controls (or a warning), the buttons, the meter, and the lens selector at the bottom.
    /// Held sideways everything stays put with its icons and text turned, except the movement controls,
    /// which move to `sideBlocks`.
    private func controls(solution: FramingSolution?, exposure: ExposureSolution, movement: MovementInfo?) -> some View {
        GeometryReader { geometry in
            let image = screenLayout(geometry, solution: solution, movement: movement).image
            let bandTop = image.maxY + ScreenLayout.gap
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if !orientation.isLandscape, setupBlockHeight(solution: solution, movement: movement) > 0 {
                    setupBlock(solution: solution, movement: movement)
                    Spacer(minLength: Self.rowSpacing)
                }
                ToolRow(rotation: orientation.rotation, showsGrid: $showsGrid, showsMovements: movementsToggle,
                        present: present)
                Spacer(minLength: Self.rowSpacing)
                MeterBar(settings: exposureSettings, solution: exposure, limits: library.exposureLimits,
                         ev100: meteredEV, readingIsClipped: camera.meterIsClipped, step: library.meterStep,
                         rotation: orientation.rotation)
                Spacer(minLength: Self.rowSpacing)
                ControlBar(present: present, rotation: orientation.rotation)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .frame(width: geometry.size.width, height: max(geometry.size.height - safeArea.bottom - bandTop, 0))
            .offset(y: bandTop)
        }
        .ignoresSafeArea()
    }

    /// The least space between rows of controls; any more room is shared out evenly.
    static let rowSpacing: CGFloat = 10

    /// The movement controls when movements are on, with a warning above them when the frame reaches
    /// past what the phone can see; otherwise that warning when the setup is too wide.
    @ViewBuilder
    private func setupBlock(solution: FramingSolution?, movement: MovementInfo?) -> some View {
        if let movement {
            VStack(spacing: 8) {
                if movement.layout.isBeyondCamera {
                    WarningTag()
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                }
                MovementBar(state: $movements, margin: movement.margin,
                            imageCircle: movement.imageCircle.map { ($0.diameter, movement.aperture, $0.isEstimate) },
                            rotation: orientation.rotation,
                            step: { delta in
                                move(movements.axis, to: movements.movement[movements.axis] + delta, info: movement)
                            },
                            resetAll: { movements.movement = .zero })
            }
            .animation(.smooth, value: movement.layout.isBeyondCamera)
            .transition(.opacity)
        } else if solution?.isClipped == true {
            WarningTag()
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
        }
    }

    /// Height of `setupBlock`, for placing it turned in landscape.
    private func setupBlockHeight(solution: FramingSolution?, movement: MovementInfo?) -> CGFloat {
        let tag = WarningTag.height
        if let movement {
            return GlassButtonMetrics.pillHeight + (movement.layout.isBeyondCamera ? 8 + tag : 0)
        }
        return solution?.isClipped == true ? tag : 0
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
            .task(id: undoableReset?.id) {
                // The undo offer lasts a few seconds.
                guard undoableReset != nil else { return }
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) { undoableReset = nil }
            }
            .onChange(of: library.selectedLensID) {
                // A new lens's nickname, if it has one, shows briefly over the image.
                let name = library.selectedLens?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                withAnimation(.smooth(duration: 0.25)) { lensNotice = name.isEmpty ? nil : (name, UUID()) }
            }
            .task(id: lensNotice?.id) {
                guard lensNotice != nil else { return }
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.4)) { lensNotice = nil }
            }
            .task {
                // The first time, name the circle in the middle of the frame.
                guard !hasSeenSpotHint else { return }
                try? await Task.sleep(for: .seconds(0.8))
                withAnimation(.easeIn(duration: 0.3)) { showsSpotHint = true }
                try? await Task.sleep(for: .seconds(4))
                withAnimation(.easeOut(duration: 0.5)) { showsSpotHint = false }
                hasSeenSpotHint = true
            }
            .onChange(of: zoom, initial: true) { _, zoom in
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
            #if DEBUG
            // For screenshots: `-TFImageCircle 90` gives the selected lens a 90 mm image circle at f/11;
            // `-TFMovements YES -TFRise 10 -TFShift 5 -TFOverview YES` opens movements.
            .task {
                let defaults = UserDefaults.standard
                // `-TFLens 23` picks the lens with that focal length.
                if let lens = library.lenses.first(where: { $0.focalLength == defaults.double(forKey: "TFLens") }) {
                    library.selectedLensID = lens.id
                }
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
                    // A new lens is typed in, so it gets the full height; lists can start at half height.
                    .presentationDetents(sheet == .newLens ? [.large] : [.medium, .large])
            }
    }

    // MARK: - Presentation

    /// Held sideways, lists open as turned cards; a new lens, which is typed in, opens as a portrait
    /// sheet so the keyboard reads the right way up.
    private func present(_ destination: Sheet) {
        if orientation.isLandscape, destination != .newLens {
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

    /// Held sideways, the movement controls (or a warning) run along the viewer's bottom edge, turned to
    /// read upright.
    @ViewBuilder
    private func sideBlocks(solution: FramingSolution?, exposure: ExposureSolution, movement: MovementInfo?) -> some View {
        if orientation.isLandscape {
            GeometryReader { geometry in
                // Distance from the screen edge to the centre of the turned block.
                let inset = 12 + setupBlockHeight(solution: solution, movement: movement) / 2
                let turnedLeft = orientation.hold == .landscapeLeft
                setupBlock(solution: solution, movement: movement)
                    .fixedSize()
                    .rotationEffect(orientation.rotation)
                    .position(x: turnedLeft ? inset : geometry.size.width - inset, y: geometry.size.height / 2)
            }
            .ignoresSafeArea()
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

    /// Where the camera image goes, around what the control bands hold now. `geometry` spans the whole
    /// screen.
    private func screenLayout(_ geometry: GeometryProxy, solution: FramingSolution?, movement: MovementInfo?) -> ScreenLayout {
        // As in `controls`: lens selector, meter, buttons and (upright) the movement controls or warning.
        let pill = GlassButtonMetrics.pillHeight
        var bottom = 8 + pill + Self.rowSpacing + MeterBar.height(turned: orientation.isLandscape) + Self.rowSpacing
            + ToolRow.height
        let setup = setupBlockHeight(solution: solution, movement: movement)
        if !orientation.isLandscape, setup > 0 {
            bottom += Self.rowSpacing + setup
        }
        return ScreenLayout.make(screen: geometry.size, safeTop: safeArea.top, safeBottom: safeArea.bottom,
                                 aspectRatio: camera.optics.aspectRatio, top: 0, bottom: bottom)
    }

    /// Where the spot meter reads, on screen and on the sensor: a tapped point, else the moved frame's
    /// centre with movements on, else the centre cross. `radius` is in points.
    private func spotPlacement(imageSize: CGSize, zoom: Double, movement: MovementInfo?,
                               mapping: MovementMapping?) -> (location: CGPoint, radius: CGFloat, region: SpotMeter.Region) {
        let optics = camera.optics
        let halfWidth = optics.tanHalfShort / zoom
        let halfLong = optics.tanHalfLong / zoom
        let radiusTan = tan(Self.spotAngle / 2 * .pi / 180)
        let pointsPerTan = mapping?.pointsPerTan ?? Double(imageSize.width) / (2 * halfWidth)
        // Radius as a share of the sensor image's width (its long side) and height.
        let radius = CGSize(width: radiusTan / (2 * halfLong), height: radiusTan / (2 * halfWidth))
        let screenRadius = CGFloat(radiusTan * pointsPerTan)

        var tanX = 0.0
        var tanY = 0.0
        var location = CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        if let movement, let mapping {
            tanX = movement.layout.frameCenterX
            tanY = movement.layout.frameCenterY
            location = mapping.point(x: tanX, y: tanY, in: imageSize)
        }
        // Portrait image position, then turned into the sensor's landscape coordinates.
        let u = 0.5 + tanX / (2 * halfWidth)
        let v = 0.5 + tanY / (2 * halfLong)
        return (location, screenRadius, SpotMeter.Region(center: CGPoint(x: v, y: 1 - u), radius: radius))
    }

    /// Dragging on the image with movements on moves the chosen axis only: in the overview the frame
    /// follows the finger; in the result view the scene does, like panning a photo.
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
                }
            }
            .onEnded { _ in
                movementDragStart = nil
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

// MARK: - Notices

/// Brief notices over the camera image, laid out the way the phone is held: the lens nickname and an
/// undo offer at the top, and the frame-size chip at the bottom, which resets the pinch when tapped.
private struct ImageNotices: View {
    let rotation: Angle
    let size: CGSize
    let lensName: String?
    let undo: String?
    let performUndo: () -> Void
    /// Frame size relative to the standard fill, when pinched away from it.
    let zoom: Double?
    let resetZoom: () -> Void

    var body: some View {
        let isTurned = rotation != .zero
        VStack(spacing: 8) {
            if let lensName {
                Text(lensName)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .glassSurface(Capsule())
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .accessibilityIdentifier("lensNotice")
            }
            if let undo {
                HStack(spacing: 12) {
                    Text(undo)
                        .font(.footnote)
                    Button("Undo", action: performUndo)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(minHeight: 44)
                }
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .glassSurface(Capsule())
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityIdentifier("undoBanner")
            }
            Spacer(minLength: 0)
            if let zoom {
                Button(action: resetZoom) {
                    Text(String(format: "%.1f×", zoom))
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 12)
                        .frame(minWidth: 44, minHeight: 32)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassSurface(Capsule(), interactive: true)
                .frame(minHeight: 44)
                .accessibilityLabel("Frame size \(String(format: "%.1f", zoom)) times")
                .accessibilityHint("Returns to the standard frame size")
                .accessibilityIdentifier("zoomChip")
                .transition(.opacity)
            }
        }
        .padding(12)
        .frame(width: isTurned ? size.height : size.width, height: isTurned ? size.width : size.height)
        // Turned only when the phone is: accessibility frames don't follow a rotation, even of 0°, so
        // VoiceOver (and taps by accessibility) would miss the buttons.
        .modifier(TurnedWhenSideways(rotation: rotation))
        .frame(width: size.width, height: size.height)
        .animation(.smooth(duration: 0.25), value: zoom == nil)
    }
}

private struct TurnedWhenSideways: ViewModifier {
    let rotation: Angle

    func body(content: Content) -> some View {
        if rotation == .zero {
            content
        } else {
            content.rotationEffect(rotation)
        }
    }
}

// MARK: - Tools

/// Round buttons above the meter, each labelled: settings, frame (format), lenses, movements and grid,
/// spread across the width. Held sideways the labels hide, as they would read sideways.
private struct ToolRow: View {
    let rotation: Angle
    @Binding var showsGrid: Bool
    @Binding var showsMovements: Bool
    let present: (ViewfinderView.Sheet) -> Void

    @Environment(LibraryStore.self) private var library

    static let height: CGFloat = GlassButtonMetrics.pillHeight + 3 + 14

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            tool("slider.horizontal.3", "Settings", id: "settingsButton") { present(.settings) }
            Spacer(minLength: 4)
            tool("aspectratio", "Frame", id: "formatButton",
                 accessibility: "Frame: \(library.selectedFormat.name)") { present(.formats) }
            Spacer(minLength: 4)
            tool("camera.aperture", "Lenses", id: "lensButton") {
                present(library.lenses.isEmpty ? .newLens : .lenses)
            }
            Spacer(minLength: 4)
            tool("arrow.up.and.down.and.arrow.left.and.right", "Movements", id: "movementsButton",
                 isOn: showsMovements) { showsMovements.toggle() }
            Spacer(minLength: 4)
            tool("grid", "Grid", id: "gridButton", isOn: showsGrid) { showsGrid.toggle() }
        }
        .frame(height: Self.height, alignment: .top)
    }

    private func tool(_ systemImage: String, _ title: String, id: String, accessibility: String? = nil,
                      isOn: Bool = false, action: @escaping () -> Void) -> some View {
        VStack(spacing: 3) {
            RoundGlassButton(systemImage: systemImage, label: accessibility ?? title, isOn: isOn,
                             rotation: rotation, action: action)
                .accessibilityIdentifier(id)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
                .lineLimit(1)
                .fixedSize()
                .frame(width: RoundGlassButton.size)
                .opacity(rotation == .zero ? 1 : 0)
                .accessibilityHidden(true)
        }
    }
}

/// Shown above the buttons when the setup, or the moved frame, is wider than the phone's camera can see.
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
