import SwiftUI

@main
struct RiddleApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var store = DiaryStore()

    init() {
        FontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(store)
                // The parchment palette is designed to read the same in light or
                // dark environments, so we pin the scheme for a consistent look.
                .preferredColorScheme(.light)
                .tint(Theme.accent)
        }
    }
}
