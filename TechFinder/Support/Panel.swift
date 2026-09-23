import SwiftUI

extension EnvironmentValues {
    /// Closes the rotated panel a view is shown in. Nil when the view is in a regular sheet.
    @Entry var closePanel: (() -> Void)?
}

/// A card that stands in for a sheet while the phone is held sideways.
///
/// The interface stays portrait so the camera image never spins, which means system sheets would appear
/// sideways. This card is turned to match how the phone is held and closes when the dimmed area around
/// it is tapped.
struct RotatedPanel<Content: View>: View {
    let rotation: Angle
    let close: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geometry in
            let isTurned = rotation != .zero
            let along = isTurned ? geometry.size.height : geometry.size.width
            let across = isTurned ? geometry.size.width : geometry.size.height
            let size = CGSize(width: min(along - 100, 620), height: across - 40)

            ZStack {
                Color.black.opacity(0.4)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)

                content
                    .environment(\.closePanel, close)
                    .frame(width: size.width, height: size.height)
                    .scrollContentBackground(.hidden)
                    .background(Color(white: 0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.4), radius: 30)
                    .rotationEffect(rotation)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }
}
