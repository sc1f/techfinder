import SwiftUI
import TechFinderCore

/// Draws the taking frame over the camera image: darkened surround, a hairline border and corner marks.
///
/// The view fills the camera image rect. The frame's long side runs along the image's long (vertical) axis.
struct FrameOverlay: View {
    let solution: FramingSolution
    var showsGrid = false

    var body: some View {
        let short = solution.shortFraction
        let long = solution.longFraction
        let accent: Color = solution.isClipped ? .orange : .white

        ZStack {
            FrameShape(part: .surround, shortFraction: short, longFraction: long)
                .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
            if showsGrid {
                FrameShape(part: .thirds, shortFraction: short, longFraction: long)
                    .stroke(.white.opacity(0.4), lineWidth: 0.5)
                    .transition(.opacity)
            }
            FrameShape(part: .border, shortFraction: short, longFraction: long)
                .stroke(accent.opacity(0.85), lineWidth: 1)
            FrameShape(part: .corners, shortFraction: short, longFraction: long)
                .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .square))
            FrameShape(part: .centerMark, shortFraction: short, longFraction: long)
                .stroke(.white.opacity(0.6), lineWidth: 1)
        }
        .clipped()
        .allowsHitTesting(false)
        .animation(.smooth(duration: 0.25), value: solution)
        .animation(.smooth(duration: 0.2), value: showsGrid)
    }
}

/// One layer of the frame drawing. The frame size animates between lenses and formats.
private struct FrameShape: Shape {
    enum Part { case surround, border, corners, centerMark, thirds }

    let part: Part
    var shortFraction: Double
    var longFraction: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(shortFraction, longFraction) }
        set {
            shortFraction = newValue.first
            longFraction = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let size = CGSize(width: rect.width * shortFraction, height: rect.height * longFraction)
        let frame = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                           width: size.width, height: size.height)
        var path = Path()

        switch part {
        case .surround:
            path.addRect(rect)
            path.addRect(frame)

        case .border:
            path.addRect(frame)

        case .corners:
            let arm = min(22, min(frame.width, frame.height) * 0.2)
            for (corner, dx, dy) in [(CGPoint(x: frame.minX, y: frame.minY), 1.0, 1.0),
                                     (CGPoint(x: frame.maxX, y: frame.minY), -1.0, 1.0),
                                     (CGPoint(x: frame.minX, y: frame.maxY), 1.0, -1.0),
                                     (CGPoint(x: frame.maxX, y: frame.maxY), -1.0, -1.0)] {
                path.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
                path.addLine(to: corner)
                path.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
            }

        case .thirds:
            for fraction in [1.0 / 3.0, 2.0 / 3.0] {
                let x = frame.minX + frame.width * fraction
                let y = frame.minY + frame.height * fraction
                path.move(to: CGPoint(x: x, y: frame.minY))
                path.addLine(to: CGPoint(x: x, y: frame.maxY))
                path.move(to: CGPoint(x: frame.minX, y: y))
                path.addLine(to: CGPoint(x: frame.maxX, y: y))
            }

        case .centerMark:
            let arm: CGFloat = 8
            path.move(to: CGPoint(x: frame.midX - arm, y: frame.midY))
            path.addLine(to: CGPoint(x: frame.midX + arm, y: frame.midY))
            path.move(to: CGPoint(x: frame.midX, y: frame.midY - arm))
            path.addLine(to: CGPoint(x: frame.midX, y: frame.midY + arm))
        }
        return path
    }
}
