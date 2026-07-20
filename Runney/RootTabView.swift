import SwiftUI

/// De vijf hoofdschermen van de app. Los van de View-structs zelf gehouden zodat de
/// navigatie (welk scherm, welk icoon, welke titel) op één centrale plek staat.
private enum AppTab: CaseIterable {
    case home, stats, runs, plan, profile

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .stats: return "chart.bar.fill"
        case .runs: return "map.fill"
        case .plan: return "calendar.badge.clock"
        case .profile: return "person.fill"
        }
    }

    var title: String {
        switch self {
        case .home: return String(localized: "Home", comment: "Tab name")
        case .stats: return String(localized: "Stats", comment: "Tab name")
        case .runs: return String(localized: "Runs", comment: "Tab name")
        case .plan: return String(localized: "Plan", comment: "Tab name")
        case .profile: return String(localized: "Profile", comment: "Tab name")
        }
    }
}

/// Het echte startpunt van de app-UI. Stap 3 van de stijlvernieuwing: vervangt de
/// systeem-tabbalk door een eigen, zwevende pil-navigatie (zie het Plan-scherm voor de
/// eerste proef van deze stijl) — Home/Runs/Plan zitten direct in de pil, Stats en Profiel
/// zitten achter de "Meer"-knop rechts, via een native Menu.
struct RootTabView: View {
    /// Expliciet doorgegeven vanuit AppRootView, i.p.v. dat ProfileView zelf de
    /// @AppStorage-vlag omzet — zo is de state-wijziging gegarandeerd op dezelfde
    /// View-instantie die bepaalt wat er getoond wordt, geen aanname over cross-view reactiviteit.
    let onResetOnboarding: () -> Void

    @State private var selectedTab: AppTab = .home
    @ObservedObject private var subscriptions = SubscriptionManager.shared

    private let pillTabs: [AppTab] = [.home, .runs, .plan]
    private let moreTabs: [AppTab] = [.stats, .profile]

    var body: some View {
        Group {
            switch selectedTab {
            case .home: HomeView()
            case .stats: StatsView()
            case .runs: RunsView()
            case .plan:
                if subscriptions.isPro {
                    PlannedRunsView()
                } else {
                    LockedTabView(
                        title: String(localized: "Planned Runs", comment: "Pro feature title"),
                        subtitle: String(localized: "Follow your own training schedule, day by day.", comment: "Pro feature subtitle"),
                        icon: "calendar.badge.clock"
                    )
                }
            case .profile: ProfileView(onResetOnboarding: onResetOnboarding)
            }
        }
        // safeAreaInset i.p.v. een ZStack-overlay: zo krijgt elk scherm automatisch de
        // juiste onderste marge (scrollviews duwen hun laatste inhoud vanzelf omhoog),
        // zonder dat elk los scherm daar zelf rekening mee moet houden.
        .safeAreaInset(edge: .bottom) {
            floatingNavBar
        }
    }

    private var floatingNavBar: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(pillTabs, id: \.self) { tab in
                    tabButton(tab)
                }
            }
            .padding(6)
            .background(CozyPalette.cardBackground)
            .clipShape(Capsule())
            // De gewone kaartstijl in de app is bewust vlak (zie CozyStyle.swift), maar dat
            // werkt daar omdat elke kaart op dezelfde effen achtergrond staat. Deze balk
            // zweeft over scrollende inhoud die van kleur kan wisselen (zie screenshot: de
            // delta-chips eronder) — zonder een eigen schaduw verdween-ie daar zowat in.
            .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 3)

            Spacer()

            Menu {
                ForEach(moreTabs, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.icon)
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(CozyPalette.cardBackground)
                        .frame(width: 48, height: 48)
                    Image(systemName: moreTabs.contains(selectedTab) ? "ellipsis.circle.fill" : "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(moreTabs.contains(selectedTab) ? CozyPalette.textPrimary : CozyPalette.textSecondary)
                }
                .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(CozyPalette.primaryButtonBackground)
                        .frame(width: 40, height: 40)
                }
                Image(systemName: tab.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? CozyPalette.primaryButtonText : CozyPalette.textSecondary)
            }
            .frame(width: 40, height: 40)
        }
        .accessibilityLabel(tab.title)
    }
}

#Preview {
    RootTabView(onResetOnboarding: {})
}

/// Volledig-scherm variant voor als een hele tab (i.p.v. één kaart tussen andere content)
/// achter Pro zit — ProGate's compacte, tussen-andere-kaarten-stijl zou hier verdwaald in een
/// verder lege pagina staan, dus dit scherm centreert zichzelf en heeft een eigen achtergrond.
private struct LockedTabView: View {
    let title: String
    let subtitle: String
    let icon: String

    @State private var showsPaywall = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(CozyPalette.level.opacity(0.2))
                    .frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(CozyPalette.level)
            }
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(CozyPalette.textPrimary)
                Text(subtitle)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(CozyPalette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                showsPaywall = true
            } label: {
                Text("Unlock with Pro")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(CozyPalette.primaryButtonText)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(CozyPalette.primaryButtonBackground)
                    .clipShape(Capsule())
            }
            Spacer()
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cozyBackground()
        .sheet(isPresented: $showsPaywall) {
            PaywallView()
        }
    }
}
