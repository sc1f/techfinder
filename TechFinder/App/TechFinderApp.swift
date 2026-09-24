import SwiftUI
import TechFinderCore

@main
struct TechFinderApp: App {
    @State private var library = Self.makeLibrary()

    var body: some Scene {
        WindowGroup {
            ViewfinderView()
                .environment(library)
                .preferredColorScheme(.dark)
                .background(KeyboardDismissal())
        }
    }

    private static func makeLibrary() -> LibraryStore {
        #if DEBUG
        // UI tests start from the starter kit every time, without touching saved data.
        if UserDefaults.standard.bool(forKey: "TFFreshLibrary") {
            return LibraryStore(fileURL: nil)
        }
        #endif
        return LibraryStore.appDefault()
    }
}
