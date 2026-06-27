import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    avatar

                    VStack(spacing: 4) {
                        Text(session.profile?.displayName ?? "Camper")
                            .font(.title2.bold())
                            .foregroundStyle(Theme.ink)
                        if let camp = session.camp {
                            Text(camp.name).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let cabin = session.profile?.cabin {
                            Text("Cabin \(cabin)").font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    pointsCard

                    Button(role: .destructive) {
                        Task { await session.signOut() }
                    } label: {
                        Text("Sign out").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 20)
                }
                .padding(Theme.screenPadding)
            }
            .background(Theme.sand.ignoresSafeArea())
            .navigationTitle("Me")
        }
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(Theme.accent.opacity(0.15)).frame(width: 96, height: 96)
            Text(initials)
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(Theme.accent)
        }
        .padding(.top, 12)
    }

    private var pointsCard: some View {
        HStack {
            Image(systemName: "star.circle.fill")
                .font(.title)
                .foregroundStyle(Theme.sunset)
            VStack(alignment: .leading) {
                Text("\(session.profile?.totalPoints ?? 0)")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.ink)
                Text("camp points earned").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.cardCorner))
    }

    private var initials: String {
        let name = session.profile?.displayName ?? "C"
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}
