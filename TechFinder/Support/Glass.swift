import SwiftUI

// Liquid Glass needs the iOS 26 SDK (Xcode 26, Swift 6.2) and iOS 26. Everywhere else the controls are
// solid dark shapes. The background is plain black either way.

/// The padding the iOS 26 glass button style puts around a label (measured from its rendering), so
/// labels can be sized to give an exact outer size.
enum GlassButtonMetrics {
    static let padding = EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12)
    /// Outer height of the top-bar pills.
    static let pillHeight: CGFloat = 48
    /// Label height that gives a `pillHeight` button once the style's padding is added.
    static var pillLabelHeight: CGFloat { pillHeight - padding.top - padding.bottom }
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

    /// The system glass button style on iOS 26 (which menus morph out of); a solid surface elsewhere,
    /// padded by the same amount so the button is the same size either way.
    @ViewBuilder
    func glassButtonStyle<S: Shape>(_ shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
                .buttonBorderShape(shape is Circle ? .circle : .capsule)
        } else {
            buttonStyle(SolidButtonStyle(shape: shape))
        }
        #else
        buttonStyle(SolidButtonStyle(shape: shape))
        #endif
    }

    /// The background of a card that stands in for a sheet: glass on iOS 26 like the system sheets,
    /// solid dark elsewhere.
    @ViewBuilder
    func panelBackground<S: Shape>(_ shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(Color(white: 0.08), in: shape)
        }
        #else
        background(Color(white: 0.08), in: shape)
        #endif
    }
}

/// Stands in for the glass button style where Liquid Glass isn't available: the same padding on a solid
/// dark shape, dimming while pressed.
private struct SolidButtonStyle<S: Shape>: ButtonStyle {
    let shape: S

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(GlassButtonMetrics.padding)
            .background(shape.fill(Color(white: 0.13)))
            .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 0.5))
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
