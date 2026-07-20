import SwiftUI

/// Herbruikbare wrapper voor een Pro-only feature. Toont de echte inhoud als de gebruiker
/// een geldig abonnement heeft, anders een "op slot"-kaart die de paywall opent bij een tik.
/// Zo hoeft elk gated scherm niet zelf de isPro-check en paywall-presentatie te herhalen —
/// zie de volgende stap voor waar dit daadwerkelijk om Level/Badges/etc. heen komt te staan.
struct ProGate<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @ViewBuilder let content: () -> Content

    @ObservedObject private var subscriptions = SubscriptionManager.shared
    @State private var showsPaywall = false

    var body: some View {
        Group {
            if subscriptions.isPro {
                content()
            } else {
                lockedCard
            }
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView()
        }
    }

    private var lockedCard: some View {
        Button {
            showsPaywall = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(CozyPalette.level.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .foregroundStyle(CozyPalette.level)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(CozyPalette.textPrimary)
                    Text(subtitle)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(CozyPalette.textSecondary)
                }
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CozyPalette.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .cozyCard()
    }
}
