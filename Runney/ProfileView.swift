import SwiftUI
import StoreKit

/// Het hoofdscherm van Profiel — bewust kort gehouden. Wat vroeger één lange lijst kaarten
/// was, is nu verdeeld over vier submenu's (zie ProfileSubmenus.swift), gegroepeerd naar
/// onderwerp. Alleen wat je waarschijnlijk het vaakst wilt zien/aanpassen (Pro-status, Badges)
/// blijft hier direct zichtbaar.
struct ProfileView: View {
    /// Vanuit AppRootView (via RootTabView) doorgegeven — direct de bron van waarheid
    /// aanpassen i.p.v. een losse @AppStorage-instantie hier die op cross-view reactiviteit moet vertrouwen.
    let onResetOnboarding: () -> Void

    @ObservedObject private var subscriptions = SubscriptionManager.shared
    @State private var showsPaywall = false
    @State private var showsManageSubscriptions = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    proCard
                    badgesCard

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Settings")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(CozyPalette.textSecondary)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            menuRow(title: "Personalization", subtitle: "Name, appearance, background color, mascot", icon: "paintbrush.fill", color: CozyPalette.consistency) {
                                PersonalizationSettingsView()
                            }
                            Divider().padding(.leading, 74)
                            menuRow(title: "Training", subtitle: "Distance unit, level display, race goal", icon: "figure.run", color: CozyPalette.stamina) {
                                TrainingSettingsView()
                            }
                            Divider().padding(.leading, 74)
                            menuRow(title: "Notifications", subtitle: "Weekly recap reminder", icon: "bell.fill", color: CozyPalette.speed) {
                                NotificationSettingsView()
                            }
                            Divider().padding(.leading, 74)
                            menuRow(title: "Support", subtitle: "Feedback, restart onboarding", icon: "questionmark.circle.fill", color: CozyPalette.level) {
                                SupportSettingsView(onResetOnboarding: onResetOnboarding)
                            }
                        }
                        .cozyCard()
                    }
                }
                .padding(20)
            }
            .cozyBackground()
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(CozyPalette.level.opacity(0.4))
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundStyle(CozyPalette.textPrimary)
                        .font(.system(size: 20, weight: .semibold))
                )

            Text("Profile")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(CozyPalette.textPrimary)

            Spacer()
        }
    }

    /// Bovenaan Profiel: nodigt uit tot upgraden zonder Pro, of laat bij een actief abonnement
    /// meteen Apple's eigen abonnementsbeheer-scherm zien (opzeggen, wijzigen, etc.) — geen
    /// eigen "annuleer abonnement"-UI nodig, dat hoort sowieso bij het systeem thuis.
    private var proCard: some View {
        Button {
            if subscriptions.isPro {
                showsManageSubscriptions = true
            } else {
                showsPaywall = true
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(CozyPalette.level.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: "star.fill")
                        .foregroundStyle(CozyPalette.level)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Runney Pro")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(CozyPalette.textPrimary)
                    Text(subscriptions.isPro ? "You're all unlocked — manage your subscription" : "Unlock levels, badges, and more")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(CozyPalette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CozyPalette.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .cozyCard()
        .sheet(isPresented: $showsPaywall) {
            PaywallView()
        }
        .manageSubscriptionsSheet(isPresented: $showsManageSubscriptions)
    }

    private var badgesCard: some View {
        ProGate(
            title: String(localized: "Badges", comment: "Pro feature title"),
            subtitle: String(localized: "Unlock 40+ milestones along the way.", comment: "Pro feature subtitle"),
            icon: "rosette"
        ) {
            NavigationLink {
                BadgesView()
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(CozyPalette.level.opacity(0.2))
                            .frame(width: 44, height: 44)
                        Image(systemName: "rosette")
                            .foregroundStyle(CozyPalette.level)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Badges")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(CozyPalette.textPrimary)
                        Text("View your earned milestones")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(CozyPalette.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CozyPalette.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .cozyCard()
        }
    }

    /// Herbruikbare rij voor de vier submenu's hieronder — icoon-cirkel, titel+ondertitel,
    /// chevron, allemaal binnen één NavigationLink. `content()` is het scherm waar de rij
    /// naartoe navigeert.
    @ViewBuilder
    private func menuRow<Content: View>(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationLink {
            content()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(title))
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(CozyPalette.textPrimary)
                    Text(LocalizedStringKey(subtitle))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(CozyPalette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CozyPalette.textSecondary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ProfileView(onResetOnboarding: {})
}
