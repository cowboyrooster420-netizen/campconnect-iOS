import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var session: SessionStore

    private enum Mode { case signIn, signUp }
    @State private var mode: Mode = .signIn
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false

    var body: some View {
        ZStack {
            Theme.sand.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    header

                    VStack(spacing: 14) {
                        if mode == .signUp {
                            field("Camp name or your name", text: $displayName, icon: "person")
                                .textInputAutocapitalization(.words)
                        }
                        field("Email", text: $email, icon: "envelope")
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        secureField("Password", text: $password)
                    }

                    if let error = session.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    PrimaryButton(
                        title: mode == .signIn ? "Sign in" : "Create account",
                        isLoading: isWorking
                    ) { Task { await submit() } }

                    Button {
                        mode = mode == .signIn ? .signUp : .signIn
                        session.errorMessage = nil
                    } label: {
                        Text(mode == .signIn
                             ? "New here? Create an account"
                             : "Already have an account? Sign in")
                            .font(.subheadline)
                    }

                    if mode == .signUp {
                        Text("Camper accounts for kids under 13 are set up by your camp with a parent's permission. Ask your camp for an invite.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(Theme.screenPadding)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "tent.fill")
                .font(.system(size: 52))
                .foregroundStyle(Theme.accent)
            Text("Campfire")
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.ink)
            Text("Your camp, all year long.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 40)
    }

    private func field(_ title: String, text: Binding<String>, icon: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(Theme.accentSoft).frame(width: 22)
            TextField(title, text: text)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }

    private func secureField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Image(systemName: "lock").foregroundStyle(Theme.accentSoft).frame(width: 22)
            SecureField(title, text: text)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }

    private func submit() async {
        isWorking = true
        defer { isWorking = false }
        switch mode {
        case .signIn:
            await session.signIn(email: email, password: password)
        case .signUp:
            await session.signUp(email: email, password: password, displayName: displayName)
        }
    }
}
