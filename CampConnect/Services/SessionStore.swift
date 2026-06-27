import Foundation
import Supabase

/// Owns authentication state and the signed-in camper's profile.
@MainActor
final class SessionStore: ObservableObject {

    enum State: Equatable {
        case loading          // checking for an existing session at launch
        case signedOut
        case signedIn
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var profile: Profile?
    @Published private(set) var camp: Camp?
    @Published var errorMessage: String?

    private let auth = SupabaseManager.shared.auth
    private var authTask: Task<Void, Never>?

    init() {
        observeAuth()
    }

    deinit { authTask?.cancel() }

    // MARK: Auth state

    private func observeAuth() {
        authTask = Task { [weak self] in
            guard let self else { return }
            for await change in auth.authStateChanges {
                switch change.event {
                case .initialSession:
                    if change.session != nil {
                        await self.loadProfile()
                        self.state = .signedIn
                    } else {
                        self.state = .signedOut
                    }
                case .signedIn:
                    await self.loadProfile()
                    self.state = .signedIn
                case .signedOut:
                    self.profile = nil
                    self.camp = nil
                    self.state = .signedOut
                default:
                    break
                }
            }
        }
    }

    // MARK: Actions

    func signIn(email: String, password: String) async {
        errorMessage = nil
        do {
            _ = try await auth.signIn(email: email, password: password)
        } catch {
            errorMessage = friendly(error)
        }
    }

    func signUp(email: String, password: String, displayName: String) async {
        errorMessage = nil
        do {
            _ = try await auth.signUp(
                email: email,
                password: password,
                data: ["display_name": .string(displayName)]
            )
        } catch {
            errorMessage = friendly(error)
        }
    }

    func signOut() async {
        try? await auth.signOut()
    }

    // MARK: Profile

    func loadProfile() async {
        do {
            let profile = try await CampService.shared.fetchMyProfile()
            self.profile = profile
            if let campID = profile.campID {
                self.camp = try await CampService.shared.fetchCamp(id: campID)
            }
        } catch {
            // A brand-new account may not have its profile row replicated yet;
            // it's created by a DB trigger. Surface but don't hard-fail the UI.
            errorMessage = friendly(error)
        }
    }

    private func friendly(_ error: Error) -> String {
        if let authError = error as? AuthError {
            return authError.localizedDescription
        }
        return error.localizedDescription
    }
}
