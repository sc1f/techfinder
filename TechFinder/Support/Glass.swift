import SwiftUI

// Liquid Glass needs the iOS 26 SDK (Xcode 26, Swift 6.2) and iOS 26. Everywhere else the app uses a
// plain black background with solid dark controls in the same shapes.

enum LiquidGlass {
    /// Whether this build and device render real Liquid Glass.
    static var isAvailable: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }
}

extension View {
    /// Places the view on a glass surface of the given shape.
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            solidSurface(shape, tint: tint)
        }
        #else
        solidSurface(shape, tint: tint)
        #endif
    }

    private func solidSurface<S: Shape>(_ shape: S, tint: Color?) -> some View {
        background {
            shape.fill(tint.map { $0.opacity(0.35) } ?? Color(white: 0.13))
        }
        .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 0.5))
    }

    /// Turns the view into a clear, lifted glass lens while `isActive`, like the iOS 26 segmented
    /// control's thumb during a drag.
    @ViewBuilder
    func glassLens<S: Shape>(_ shape: S, isActive: Bool) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            glassEffect(isActive ? Glass.clear.interactive() : .identity, in: shape)
        } else {
            overlay(shape.stroke(.white.opacity(isActive ? 0.35 : 0), lineWidth: 1))
        }
        #else
        overlay(shape.stroke(.white.opacity(isActive ? 0.35 : 0), lineWidth: 1))
        #endif
    }
}
