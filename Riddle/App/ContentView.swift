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
            // Pure ink on paper. The guide is summoned by a two-finger tap or a
            // drawn "?"; the corner mark only wakes an unbound diary.
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

    /// No visible chrome once the diary is awake. Before a key is bound, leave
    /// only a faint moon-mark so the first opening has somewhere to begin.
    private var seal: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    // No voice yet? Go straight to the key. Otherwise, the guide.
                    if settings.apiKeyIsSet { showGuide = true } else { showSettings = true }
                } label: {
                    if settings.apiKeyIsSet {
                        Color.clear
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    } else {
                        Image(systemName: "moon.zzz")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.ink.opacity(0.42))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Guide")
            }
            Spacer()
        }
        .padding(.trailing, 18)
        .padding(.top, 6)
    }
}
