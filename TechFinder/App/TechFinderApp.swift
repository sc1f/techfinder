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
            // Viewfinder settings start fresh too, past the welcome unless `-TFWelcome YES`.
            for key in ["frameFill", "showsGrid"] { UserDefaults.standard.removeObject(forKey: key) }
            UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "TFWelcome"), forKey: "hasSeenWelcome")
            let library = LibraryStore(fileURL: nil)
            // `-TFLenses 28,40,65,80,150` replaces the starter lenses.
            if let list = UserDefaults.standard.string(forKey: "TFLenses") {
                for lens in library.lenses { library.deleteLens(id: lens.id) }
                for focalLength in list.split(separator: ",").compactMap({ Double($0) }) {
                    library.save(Lens(name: "", focalLength: focalLength))
                }
                library.selectedLensID = library.lenses.first?.id
            }
            return library
        }
        #endif
        return LibraryStore.appDefault()
    }
}
