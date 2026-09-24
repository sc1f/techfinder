import CoreGraphics

/// Where the camera image and the controls go on the phone's screen, in portrait points.
///
/// The controls live in the black bands above and below the camera image and never cover it: the tools
/// above; below, within thumb reach, the movement controls, the meter and the lens row. The image is
/// centred when that leaves room, moved up or down when one band is short, and made smaller when the
/// screen is too short for both bands (an iPhone SE). Held sideways, the meter stands in a column in the
/// band between the image and the lens row, as wide as the band allows.
public struct ScreenLayout: Equatable, Sendable {
    /// Heights of the portrait control blocks, matching the views.
    public struct Metrics: Equatable, Sendable {
        /// The tool row, from the top of the safe area.
        public var top: CGFloat = 8 + 40
        /// The lens row, from the bottom of the safe area.
        public var lensRow: CGFloat = 8 + 48
        /// Movement controls and meter above the lens row.
        public var aboveLensRow: CGFloat = 12 + 40 + 12 + 48
        /// Clear space between the controls and the camera image.
        public var gap: CGFloat = 8
        /// Landscape meter column width: at least wide enough for a meter value.
        public var columnWidth: ClosedRange<CGFloat> = 88...120

        public var bottom: CGFloat { lensRow + aboveLensRow }

        public init() {}
    }

    /// The camera image, upright.
    public var image: CGRect
    /// Landscape: the width of the meter column (its extent across the band) and the y of its centre.
    public var columnWidth: CGFloat
    public var columnCenterY: CGFloat

    /// - Parameters:
    ///   - screen: The full screen in portrait points.
    ///   - safeTop: Top safe area inset (status bar, notch or Dynamic Island).
    ///   - safeBottom: Bottom safe area inset (home indicator).
    ///   - aspectRatio: The camera image's long side over its short side.
    public static func make(screen: CGSize, safeTop: CGFloat, safeBottom: CGFloat, aspectRatio: Double,
                            metrics: Metrics = Metrics()) -> ScreenLayout {
        guard screen.width > 0, screen.height > 0, aspectRatio > 0 else {
            return ScreenLayout(image: .zero, columnWidth: metrics.columnWidth.lowerBound, columnCenterY: 0)
        }
        let minTop = safeTop + metrics.top + metrics.gap
        let maxBottom = screen.height - safeBottom - metrics.bottom - metrics.gap

        // Full width, unless that is taller than the room between the bands.
        var size = CGSize(width: screen.width, height: screen.width * CGFloat(aspectRatio))
        let room = max(maxBottom - minTop, 0)
        if size.height > room {
            size = CGSize(width: room / CGFloat(aspectRatio), height: room)
        }
        let centred = (screen.height - size.height) / 2
        let y = min(max(centred, minTop), maxBottom - size.height)
        let image = CGRect(x: (screen.width - size.width) / 2, y: y, width: size.width, height: size.height)

        // The column sits between the image and the lens row.
        let bandTop = image.maxY + metrics.gap
        let bandBottom = screen.height - safeBottom - metrics.lensRow - metrics.gap
        let width = min(max(bandBottom - bandTop, metrics.columnWidth.lowerBound), metrics.columnWidth.upperBound)
        return ScreenLayout(image: image, columnWidth: width, columnCenterY: (bandTop + bandBottom) / 2)
    }

    /// The lens row's top edge, for a screen of `height` with `safeBottom`.
    public static func lensRowTop(height: CGFloat, safeBottom: CGFloat, metrics: Metrics = Metrics()) -> CGFloat {
        height - safeBottom - metrics.lensRow
    }
}
