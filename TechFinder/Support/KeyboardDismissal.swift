import SwiftUI
import UIKit

/// Dismisses the keyboard when the user taps anywhere that isn't a text input, in every screen and
/// sheet: a tap recogniser on the window that lets touches through to whatever was tapped.
struct KeyboardDismissal: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView {
        InstallerView()
    }

    func updateUIView(_ view: InstallerView, context: Context) {}

    final class InstallerView: UIView, UIGestureRecognizerDelegate {
        private weak var installedWindow: UIWindow?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, window !== installedWindow else { return }
            installedWindow = window
            let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
        }

        @objc private func dismissKeyboard() {
            // After the tapped control has handled the tap, so a button pressed while the keyboard is up
            // still works even though the layout shifts as the keyboard goes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.installedWindow?.endEditing(true)
            }
        }

        /// Taps on a text field or text view go to it as normal.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

extension View {
    /// Adds a Done button above the keyboard, for number pads that have no return key.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}
