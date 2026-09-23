import SwiftUI
import TechFinderCore

@main
struct TechFinderApp: App {
    @State private var library = LibraryStore.appDefault()

    var body: some Scene {
        WindowGroup {
            ViewfinderView()
                .environment(library)
                .preferredColorScheme(.dark)
        }
    }
}
