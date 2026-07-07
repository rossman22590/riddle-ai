import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings

    private enum Route { case none, settings, history }

    @State private var showGuide = false
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var route: Route = .none
    @State private var coverClosed = true       // the diary greets every opening closed

    var body: some View {
        ZStack {
            // Pure ink on paper — no chrome at all. The guide is summoned by a
            // two-finger tap or a drawn "?"; writing on a voiceless diary opens
            // the guide too, so an unbound diary still has somewhere to begin.
            DiaryView(
                onSummonGuide: { showGuide = true },
                onOpenMemory: { showHistory = true }
            )

            // The closed cover, filling the screen until the writer touches it.
            if coverClosed {
                DiaryGate { coverClosed = false }
                    .zIndex(1)
            }
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-openSettings") { showSettings = true }
        }
        .sheet(isPresented: $showGuide, onDismiss: {
            switch route {
            case .settings: showSettings = true
            case .history:  showHistory = true
            case .none:     break
            }
            route = .none
        }) {
            GuideView(
                onSettings: { route = .settings; showGuide = false },
                onHistory: { route = .history; showGuide = false }
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(onCloseDiary: { coverClosed = true })
        }
        .sheet(isPresented: $showHistory) { HistoryView() }
    }
}
