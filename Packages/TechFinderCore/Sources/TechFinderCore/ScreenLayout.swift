import CoreGraphics

/// Where the camera image goes on the phone's screen, in portrait points, around the controls above and
/// below it.
///
/// The controls live in black bands and never cover the image. The top band is only as tall as what is
/// in it (nothing but the safe area when all the controls are at the bottom) and the image sits right
/// under it; the bottom band takes the rest, which the controls share out. When the bottom band would be
/// shorter than its controls need (an iPhone SE with movements on) the image gets smaller.
public struct ScreenLayout: Equatable, Sendable {
    /// Clear space between the controls and the camera image.
    public static let gap: CGFloat = 8

    /// The camera image, upright.
    public var image: CGRect

    /// - Parameters:
    ///   - screen: The full screen in portrait points.
    ///   - safeTop: Top safe area inset (status bar, notch or Dynamic Island).
    ///   - safeBottom: Bottom safe area inset (home indicator).
    ///   - aspectRatio: The camera image's long side over its short side.
    ///   - top: Height of the controls below the top of the safe area.
    ///   - bottom: The least height the controls above the bottom of the safe area need.
    public static func make(screen: CGSize, safeTop: CGFloat, safeBottom: CGFloat, aspectRatio: Double,
                            top: CGFloat, bottom: CGFloat) -> ScreenLayout {
        guard screen.width > 0, screen.height > 0, aspectRatio > 0 else { return ScreenLayout(image: .zero) }
        let minTop = safeTop + top + gap
        let maxBottom = screen.height - safeBottom - bottom - gap

        // Full width, unless that is taller than the room between the bands.
        var size = CGSize(width: screen.width, height: screen.width * CGFloat(aspectRatio))
        let room = max(maxBottom - minTop, 0)
        if size.height > room {
            size = CGSize(width: room / CGFloat(aspectRatio), height: room)
        }
        return ScreenLayout(image: CGRect(x: (screen.width - size.width) / 2, y: minTop,
                                          width: size.width, height: size.height))
    }
}
