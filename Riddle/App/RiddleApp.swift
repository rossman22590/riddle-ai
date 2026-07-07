import SwiftUI

@main
struct RiddleApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var store = DiaryStore()
    @StateObject private var session = DiarySession()
    @StateObject private var soul = MemorySoul()

    init() {
        FontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(store)
                .environmentObject(session)
                .environmentObject(soul)
                // The parchment palette is designed to read the same in light or
                // dark environments, so we pin the scheme for a consistent look.
                .preferredColorScheme(.light)
                .tint(Theme.accent)
        }
    }
}
