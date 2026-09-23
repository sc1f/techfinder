import SwiftUI

// Liquid Glass needs the iOS 26 SDK (Xcode 26, Swift 6.2). Older toolchains and older iOS versions
// get a blurred material that keeps the same shapes and layout.

extension View {
    /// Places the view on a glass surface of the given shape.
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            materialSurface(shape, tint: tint)
        }
        #else
        materialSurface(shape, tint: tint)
        #endif
    }

    private func materialSurface<S: Shape>(_ shape: S, tint: Color?) -> some View {
        background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                if let tint {
                    shape.fill(tint.opacity(0.35))
                }
            }
        }
        .overlay(shape.stroke(.white.opacity(0.15), lineWidth: 0.5))
    }
}

extension View {
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
