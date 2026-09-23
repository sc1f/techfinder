import SwiftUI

/// A short explanation shown while a control is pressed and held.
struct HoldTip: Equatable {
    enum Placement { case top, bottom }

    var title: String
    var detail: String?
    /// Where the bubble appears: under the top bar or above the lens carousel.
    var placement: Placement = .bottom
}

/// A control that runs `action` on tap and shows `tip` on a long press, instead of a context menu.
struct HoldTipControl<Label: View>: View {
    let tip: HoldTip
    @Binding var shownTip: HoldTip?
    let action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        label
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 12) {
                shownTip = tip
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(tip.title)
            .accessibilityHint(tip.detail ?? "")
            .accessibilityAction(.default, action)
    }
}

/// The bubble that presents a `HoldTip`.
struct HoldTipBubble: View {
    let tip: HoldTip

    var body: some View {
        VStack(spacing: 2) {
            Text(tip.title)
                .font(.footnote.weight(.semibold))
            if let detail = tip.detail {
                Text(detail)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassSurface(Capsule())
        .fixedSize()
    }
}
