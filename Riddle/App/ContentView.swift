import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings

    private enum Route { case none, settings, history }

    @State private var showGuide = false
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var route: Route = .none

    var body: some View {
        ZStack {
            // Pure ink on paper. The guide is summoned by a two-finger tap, a
            // drawn "?", or the discreet seal in the corner.
            DiaryView(onSummonGuide: { showGuide = true })

            seal
        }
        .fullScreenCover(isPresented: .constant(!settings.hasOnboarded)) {
            OnboardingView { settings.hasOnboarded = true }
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
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showHistory) { HistoryView() }
    }

    /// A faint wax-seal-like mark, top-trailing — the discoverable way into the
    /// guide (and thus the key). When the diary has no voice yet, it glows a
    /// little to invite a tap.
    private var seal: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    // No voice yet? Go straight to the key. Otherwise, the guide.
                    if settings.apiKeyIsSet { showGuide = true } else { showSettings = true }
                } label: {
                    Image(systemName: settings.apiKeyIsSet ? "questionmark" : "moon.zzz")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.ink.opacity(settings.apiKeyIsSet ? 0.4 : 0.62))
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(Theme.ink.opacity(0.1), lineWidth: 1))
                }
                .accessibilityLabel("Guide")
            }
            Spacer()
        }
        .padding(.trailing, 18)
        .padding(.top, 6)
    }
}
