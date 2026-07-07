import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings

    private enum Route { case none, settings, history }

    @State private var showGuide = false
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var route: Route = .none
    @State private var coverClosed = true       // the diary greets every opening closed
    @State private var showMarks = false        // the one-time (replayable) lesson in the marks

    var body: some View {
        ZStack {
            // Pure ink on paper — no chrome at all. The guide is summoned by a
            // two-finger tap or a drawn "?"; writing on a voiceless diary opens
            // the guide too, so an unbound diary still has somewhere to begin.
            DiaryView(
                onSummonGuide: { showGuide = true },
                onOpenMemory: { showHistory = true }
            )

            // The marks, taught in ink the first time the diary is opened.
            if showMarks {
                RitualMarksView { withAnimation(.easeInOut(duration: 0.5)) { showMarks = false } }
                    .transition(.opacity)
                    .zIndex(2)
            }

            // The closed cover, filling the screen until the writer touches it.
            if coverClosed {
                DiaryGate { openDiary() }
                    .zIndex(3)
            }
        }
        .statusBarHidden(true)          // no iOS clock/battery over the diary — just ink and paper
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
            SettingsView(
                onCloseDiary: { coverClosed = true },
                onShowMarks: { withAnimation(.easeInOut(duration: 0.5)) { showMarks = true } }
            )
        }
        .sheet(isPresented: $showHistory) { HistoryView() }
    }

    /// Opening the cover reveals the page — and, the very first time, teaches
    /// the marks in ink before the diary is used.
    private func openDiary() {
        coverClosed = false
        guard !settings.hasSeenMarks else { return }
        settings.hasSeenMarks = true
        withAnimation(.easeInOut(duration: 0.5)) { showMarks = true }
    }
}
