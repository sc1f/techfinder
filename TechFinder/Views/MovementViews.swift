import SwiftUI
import TechFinderCore

/// The movement controls' state for the session.
struct MovementState: Equatable {
    var isOn = false
    var axis: MovementAxis = .rise
    var movement = Movement.zero
    /// Zoomed out to the whole image circle, instead of showing the moved frame as the photo.
    var showsOverview = false
}

/// How the movement view maps tangent-space positions onto the camera image: points per tangent unit,
/// and the tangent position shown at the centre.
struct MovementMapping: Equatable {
    var pointsPerTan: Double
    var originX: Double
    var originY: Double

    /// Overview: the phone image as it is, or smaller when the image circle or the frame reaches past
    /// what the phone can see, so all of it shows. Result: zoomed and panned so the moved frame is
    /// centred and fills `fill` of the image.
    static func make(layout: MovementLayout, imageSize: CGSize, showsOverview: Bool, fill: Double = 0.85) -> MovementMapping {
        let base = Double(imageSize.width) / (2 * layout.imageHalfWidth)
        guard layout.frameHalfWidth > 0, layout.frameHalfHeight > 0 else {
            return MovementMapping(pointsPerTan: base, originX: 0, originY: 0)
        }
        if showsOverview {
            let reach = 0.96 * min(Double(imageSize.width) / (2 * layout.reachHalfWidth),
                                   Double(imageSize.height) / (2 * layout.reachHalfHeight))
            return MovementMapping(pointsPerTan: min(base, reach), originX: 0, originY: 0)
        }
        let scale = fill * min(Double(imageSize.width) / (2 * layout.frameHalfWidth * base),
                               Double(imageSize.height) / (2 * layout.frameHalfHeight * base))
        return MovementMapping(pointsPerTan: base * scale, originX: layout.frameCenterX, originY: layout.frameCenterY)
    }

    /// How much the camera image must be magnified and moved to match this mapping.
    func imageTransform(layout: MovementLayout, imageSize: CGSize) -> (scale: CGFloat, offset: CGSize) {
        let base = Double(imageSize.width) / (2 * layout.imageHalfWidth)
        let scale = pointsPerTan / base
        return (CGFloat(scale), CGSize(width: -originX * pointsPerTan, height: -originY * pointsPerTan))
    }

    func point(x: Double, y: Double, in size: CGSize) -> CGPoint {
        CGPoint(x: Double(size.width) / 2 + (x - originX) * pointsPerTan,
                y: Double(size.height) / 2 + (y - originY) * pointsPerTan)
    }

    /// The inverse of `point`: a location on the image back to tangent units.
    func tangent(at location: CGPoint, in size: CGSize) -> (x: Double, y: Double) {
        ((Double(location.x) - Double(size.width) / 2) / pointsPerTan + originX,
         (Double(location.y) - Double(size.height) / 2) / pointsPerTan + originY)
    }
}

/// Draws movements over the camera image: the lens's image circle (everything outside it darkened), the
/// unmoved frame as a dashed outline, and the moved frame with its surround dimmed. Corners outside the
/// circle turn red; the circle turns orange as the frame nears its edge.
struct MovementOverlay: View, Animatable {
    let layout: MovementLayout
    var mapping: MovementMapping
    /// Millimetres between the furthest corner and the image circle edge, if the circle is known.
    let margin: Double?
    let showsGrid: Bool

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(mapping.pointsPerTan, AnimatablePair(mapping.originX, mapping.originY)) }
        set {
            mapping.pointsPerTan = newValue.first
            mapping.originX = newValue.second.first
            mapping.originY = newValue.second.second
        }
    }

    static let closeMargin = 3.0

    var body: some View {
        Canvas { context, size in
            let bounds = Path(CGRect(origin: .zero, size: size))
            let frame = rect(centerX: layout.frameCenterX, centerY: layout.frameCenterY, in: size)
            let home = rect(centerX: 0, centerY: 0, in: size)

            // Beyond the phone camera's view, even at its widest: hatched, with the edge marked.
            let cameraTopLeft = mapping.point(x: -layout.imageHalfWidth, y: -layout.imageHalfHeight, in: size)
            let cameraBottomRight = mapping.point(x: layout.imageHalfWidth, y: layout.imageHalfHeight, in: size)
            let camera = CGRect(x: cameraTopLeft.x, y: cameraTopLeft.y,
                                width: cameraBottomRight.x - cameraTopLeft.x, height: cameraBottomRight.y - cameraTopLeft.y)
            let showsBeyond = !camera.insetBy(dx: -0.5, dy: -0.5).contains(CGRect(origin: .zero, size: size))
            if showsBeyond {
                var beyond = bounds
                beyond.addRect(camera)
                context.fill(beyond, with: .color(.black), style: FillStyle(eoFill: true))
                context.drawLayer { layer in
                    layer.clip(to: beyond, style: FillStyle(eoFill: true))
                    var hatch = Path()
                    let step: CGFloat = 9
                    var x = -size.height
                    while x < size.width {
                        hatch.move(to: CGPoint(x: x, y: size.height))
                        hatch.addLine(to: CGPoint(x: x + size.height, y: 0))
                        x += step
                    }
                    layer.stroke(hatch, with: .color(.white.opacity(0.16)), lineWidth: 1)
                }
                context.stroke(Path(camera), with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }

            // Outside the image circle: not captured by the lens.
            var circlePath: Path?
            if let radius = layout.circleRadius {
                let center = mapping.point(x: 0, y: 0, in: size)
                let r = radius * mapping.pointsPerTan
                let circle = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
                circlePath = circle
                var outside = bounds
                outside.addPath(circle)
                context.fill(outside, with: .color(.black.opacity(0.7)), style: FillStyle(eoFill: true))
            }

            // Inside the circle but outside the moved frame: dimmed like the normal viewfinder.
            var surround = circlePath ?? bounds
            surround.addRect(frame)
            context.fill(surround, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))

            if let circlePath {
                let color: Color = (margin ?? 1) < 0 ? .red : ((margin ?? .infinity) < Self.closeMargin ? .orange : .white.opacity(0.55))
                context.stroke(circlePath, with: .color(color), lineWidth: 1.5)
                // The lens axis.
                let center = mapping.point(x: 0, y: 0, in: size)
                var axis = Path()
                axis.move(to: CGPoint(x: center.x - 6, y: center.y))
                axis.addLine(to: CGPoint(x: center.x + 6, y: center.y))
                axis.move(to: CGPoint(x: center.x, y: center.y - 6))
                axis.addLine(to: CGPoint(x: center.x, y: center.y + 6))
                context.stroke(axis, with: .color(.white.opacity(0.5)), lineWidth: 1)
            }

            // Where the frame would be without movements.
            if home != frame {
                context.stroke(Path(home), with: .color(.white.opacity(0.4)),
                               style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }

            if showsGrid {
                var thirds = Path()
                for fraction in [1.0 / 3.0, 2.0 / 3.0] {
                    let x = frame.minX + frame.width * fraction
                    let y = frame.minY + frame.height * fraction
                    thirds.move(to: CGPoint(x: x, y: frame.minY))
                    thirds.addLine(to: CGPoint(x: x, y: frame.maxY))
                    thirds.move(to: CGPoint(x: frame.minX, y: y))
                    thirds.addLine(to: CGPoint(x: frame.maxX, y: y))
                }
                context.stroke(thirds, with: .color(.white.opacity(0.4)), lineWidth: 0.5)
            }

            // The moved frame.
            context.stroke(Path(frame), with: .color(.white.opacity(0.9)), lineWidth: 1)
            let arm = min(22, min(frame.width, frame.height) * 0.2)
            var corners = Path()
            for (corner, dx, dy) in [(CGPoint(x: frame.minX, y: frame.minY), 1.0, 1.0),
                                     (CGPoint(x: frame.maxX, y: frame.minY), -1.0, 1.0),
                                     (CGPoint(x: frame.minX, y: frame.maxY), 1.0, -1.0),
                                     (CGPoint(x: frame.maxX, y: frame.maxY), -1.0, -1.0)] {
                corners.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
                corners.addLine(to: corner)
                corners.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
            }
            context.stroke(corners, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .square))

            // Corners outside the image circle.
            if let radius = layout.circleRadius {
                for (x, y) in cornerTangents() where hypot(x, y) > radius + 1e-9 {
                    let p = mapping.point(x: x, y: y, in: size)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(.red))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func rect(centerX: Double, centerY: Double, in size: CGSize) -> CGRect {
        let topLeft = mapping.point(x: centerX - layout.frameHalfWidth, y: centerY - layout.frameHalfHeight, in: size)
        let bottomRight = mapping.point(x: centerX + layout.frameHalfWidth, y: centerY + layout.frameHalfHeight, in: size)
        return CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
    }

    private func cornerTangents() -> [(Double, Double)] {
        [(-1.0, -1.0), (1, -1), (-1, 1), (1, 1)].map { sx, sy in
            (layout.frameCenterX + sx * layout.frameHalfWidth, layout.frameCenterY + sy * layout.frameHalfHeight)
        }
    }
}

/// Controls for movements: which axis to move, its value in millimetres with step arrows, and the
/// overview toggle. Only the chosen axis moves, so one axis can be set and then the other.
struct MovementBar: View {
    @Binding var state: MovementState
    /// Room to the image circle edge in mm, if the lens's image circle is known.
    let margin: Double?
    /// The image circle in use: diameter, the aperture it's taken at, and whether it's an estimate.
    let imageCircle: (diameter: Double, aperture: Double, isEstimate: Bool)?
    /// Moves the chosen axis by a number of millimetres, stopping at the limits.
    let step: (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                axisButton(.rise, title: "Rise")
                axisButton(.shift, title: "Shift")
            }
            MovementDial(value: state.movement[state.axis], caption: caption, captionColor: captionColor,
                         step: step, reset: { step(-state.movement[state.axis]) })
            Button {
                withAnimation(.smooth(duration: 0.35)) { state.showsOverview.toggle() }
            } label: {
                Image(systemName: state.showsOverview ? "viewfinder" : "circle.dashed")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(state.showsOverview ? Color.accentColor : .white)
                    .frame(width: 24, height: GlassButtonMetrics.pillLabelHeight)
            }
            .glassButtonStyle(Capsule())
            .accessibilityLabel(state.showsOverview ? "Show Result" : "Show Image Circle")
            .accessibilityIdentifier("overviewButton")
        }
    }

    private var caption: String {
        guard let margin, let imageCircle else { return "No image circle" }
        let circle = "IC \(Millimetres.label(imageCircle.diameter))\(imageCircle.isEstimate ? "*" : "") f/\(Millimetres.label(imageCircle.aperture))"
        if margin < 0 { return "\(circle) · outside" }
        return "\(Millimetres.label(margin)) mm to edge · \(circle)"
    }

    private var captionColor: Color {
        guard let margin else { return .secondary }
        return margin < 0 ? .red : (margin < MovementOverlay.closeMargin ? .orange : .secondary)
    }

    private func axisButton(_ axis: MovementAxis, title: String) -> some View {
        Button {
            state.axis = axis
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(state.axis == axis ? Color.accentColor : .white)
                .frame(height: GlassButtonMetrics.pillLabelHeight)
        }
        .glassButtonStyle(Capsule())
        .accessibilityAddTraits(state.axis == axis ? .isSelected : [])
        .accessibilityIdentifier("axis-\(axis.rawValue)")
    }
}

/// The chosen axis's movement with step arrows; swipe along it to move further, tap to return to zero.
private struct MovementDial: View {
    let value: Double
    let caption: String
    let captionColor: Color
    let step: (Double) -> Void
    let reset: () -> Void

    @State private var swipeSteps = 0

    private let increment = 0.5
    private let stepDistance: CGFloat = 12

    var body: some View {
        HStack(spacing: 0) {
            arrow("chevron.left") { step(-increment) }
            VStack(spacing: 0) {
                Text(caption)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(captionColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: reset)
            .gesture(swipe)
            arrow("chevron.right") { step(increment) }
        }
        .frame(minWidth: 120)
        .frame(height: GlassButtonMetrics.pillHeight)
        .glassSurface(Capsule(), interactive: true)
        .animation(.smooth(duration: 0.15), value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Movement")
        .accessibilityValue(label)
        .accessibilityAdjustableAction { direction in
            step(direction == .increment ? increment : -increment)
        }
        .accessibilityIdentifier("movementDial")
    }

    private var label: String {
        value == 0 ? "0 mm" : String(format: "%+.1f mm", value)
    }

    private func arrow(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 24)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { drag in
                let steps = Int((drag.translation.width / stepDistance).rounded(.towardZero))
                if steps != swipeSteps {
                    step(Double(steps - swipeSteps) * increment)
                    swipeSteps = steps
                }
            }
            .onEnded { _ in swipeSteps = 0 }
    }
}
