import SwiftUI
import TechFinderCore

/// Stand-in for the camera image when no camera exists (Simulator).
///
/// Draws a horizon with angle lines every 10° as seen through the zoomed phone camera, so the frame's
/// edges can be checked against the lens's angle of view: a 50 mm lens on full frame spans 39.6°, so its
/// long edges should sit just inside the ±20° lines.
struct SimulatedScene: View {
    let optics: CameraOptics
    let zoom: Double

    var body: some View {
        Canvas { context, size in
            // Portrait image: horizontal = sensor short side, vertical = long side.
            let tanX = optics.tanHalfShort / zoom
            let tanY = optics.tanHalfLong / zoom
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            func x(_ degrees: Double) -> CGFloat { center.x + CGFloat(tan(degrees * .pi / 180) / tanX) * size.width / 2 }
            func y(_ degrees: Double) -> CGFloat { center.y - CGFloat(tan(degrees * .pi / 180) / tanY) * size.height / 2 }

            let full = CGRect(origin: .zero, size: size)
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: center.y)),
                         with: .linearGradient(Gradient(colors: [Color(red: 0.16, green: 0.24, blue: 0.38), Color(red: 0.45, green: 0.55, blue: 0.66)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: center.y)))
            context.fill(Path(CGRect(x: 0, y: center.y, width: size.width, height: size.height - center.y)),
                         with: .color(Color(red: 0.18, green: 0.2, blue: 0.17)))

            var lines = Path()
            for degrees in stride(from: -80.0, through: 80.0, by: 10.0) {
                lines.move(to: CGPoint(x: x(degrees), y: 0))
                lines.addLine(to: CGPoint(x: x(degrees), y: size.height))
                lines.move(to: CGPoint(x: 0, y: y(degrees)))
                lines.addLine(to: CGPoint(x: size.width, y: y(degrees)))
            }
            context.stroke(lines, with: .color(.white.opacity(0.18)), lineWidth: 0.5)

            for degrees in stride(from: -80.0, through: 80.0, by: 10.0) where degrees != 0 {
                let label = Text("\(Int(abs(degrees)))°").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                let px = x(degrees)
                if full.insetBy(dx: 8, dy: 0).contains(CGPoint(x: px, y: center.y)) {
                    context.draw(label, at: CGPoint(x: px, y: center.y + 8))
                }
            }
        }
    }
}
