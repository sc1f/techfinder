import SwiftUI
import TechFinderCore

/// The first-launch screen: what TechFinder does in three lines, then straight to choosing a format or
/// to the viewfinder. The camera permission prompt follows it, with the reason already given.
struct WelcomeView: View {
    @Environment(LibraryStore.self) private var library
    /// Closes the welcome; `choosingFormat` opens the format picker next.
    let finish: (_ choosingFormat: Bool) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text("TechFinder")
                        .font(.largeTitle.weight(.bold))
                    Text("A viewfinder for your technical camera, on your iPhone.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 20) {
                    row("aspectratio", "Your frame",
                        "Choose your digital back or film format. The frame shows what it will capture.")
                    row("camera.aperture", "Your lenses",
                        "Add the lenses you carry and switch between them under the image.")
                    row("arrow.up.and.down.and.arrow.left.and.right", "Meter and movements",
                        "Meter the frame, and plan rise and shift within each lens's image circle.")
                }

                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    Button {
                        finish(true)
                    } label: {
                        Text("Choose Your Format")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .foregroundStyle(.black)
                    .accessibilityIdentifier("welcomeChooseFormat")

                    Button {
                        finish(false)
                    } label: {
                        Text("Continue with \(library.selectedFormat.name)")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityIdentifier("welcomeContinue")

                    Text("Next, TechFinder asks to use the camera for the viewfinder. Nothing is recorded or shared.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 48)
            .padding(.bottom, 20)
            .frame(maxWidth: 520)
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ systemImage: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
