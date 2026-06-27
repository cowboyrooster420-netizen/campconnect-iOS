import SwiftUI

/// Routes between the auth flow and the main tab experience based on session state.
struct RootView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        switch session.state {
        case .loading:
            VStack(spacing: 16) {
                Image(systemName: "tent.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.accent)
                ProgressView()
            }
        case .signedOut:
            AuthView()
        case .signedIn:
            MainTabView()
        }
    }
}

/// The three structured loops a camper lives in — no feed, no social tab.
struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Challenges", systemImage: "flag.checkered") }
            BadgesView()
                .tabItem { Label("Badges", systemImage: "rosette") }
            ProfileView()
                .tabItem { Label("Me", systemImage: "person.fill") }
        }
    }
}
