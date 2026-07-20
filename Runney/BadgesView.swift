import SwiftUI

struct BadgesView: View {
    @ObservedObject private var healthKit = HealthKitManager.shared
    @ObservedObject private var store = GameStatsStore.shared

    /// Uit GameStatsStore, die dit al berekend heeft toen runs/lifetimeRuns voor het laatst
    /// wijzigden. Zonder deze cache riep dit `evaluate` voor élke badge opnieuw aan bij élke
    /// redraw — en `streakMilestone` simuleert daarbij dag voor dag terug vanaf de eerste run,
    /// wat merkbaar traag wordt zodra iemand een jaar aan geschiedenis heeft.
    private var statuses: [BadgeStatus] {
        store.badgeStatuses
    }

    private var unlockedCount: Int {
        statuses.filter(\.isUnlocked).count
    }

    /// Groepeert per categorie in de vaste volgorde van BadgeCategory.allCases, met behoud van
    /// de oorspronkelijke volgorde binnen elke groep (Dictionary(grouping:) bewaart de
    /// encounter-volgorde van de bronrij, dus geen aparte sortering nodig). Een categorie
    /// zonder badges (zou nu niet voorkomen, maar toekomstbestendig) wordt overgeslagen.
    private var groupedStatuses: [BadgeCategoryGroup] {
        let grouped = Dictionary(grouping: statuses) { $0.definition.category }
        return BadgeCategory.allCases.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return BadgeCategoryGroup(category: category, statuses: items)
        }
    }

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                summaryCard

                ForEach(groupedStatuses) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        categoryHeader(for: group)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(group.statuses) { status in
                                BadgeTile(status: status)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .cozyBackground()
        .navigationTitle("Badges")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await healthKit.refreshAll()
        }
    }

    private var summaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(unlockedCount) / \(statuses.count) unlocked")
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(CozyPalette.textPrimary)
                Text("Keep running to unlock more.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(CozyPalette.textSecondary)
            }
            Spacer()
        }
        .cozyCard()
    }

    /// Zelfde visuele taal als de sectiekoppen op Home (label — lijn — teller), hier lokaal
    /// gehouden i.p.v. gedeeld met HomeView.swift, waar dat een private struct is.
    private func categoryHeader(for group: BadgeCategoryGroup) -> some View {
        HStack(spacing: 8) {
            Text(group.category.title)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(CozyPalette.textSecondary)

            Rectangle()
                .fill(CozyPalette.textSecondary.opacity(0.25))
                .frame(height: 1)

            Text("\(group.statuses.filter(\.isUnlocked).count)/\(group.statuses.count)")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textSecondary)
        }
        .padding(.horizontal, 4)
    }
}

/// Eén categorie met z'n badges, in de volgorde waarin ze in BadgeDefinition.all voorkomen.
private struct BadgeCategoryGroup: Identifiable {
    let category: BadgeCategory
    let statuses: [BadgeStatus]
    var id: String { category.id }
}

private struct BadgeTile: View {
    let status: BadgeStatus

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(status.isUnlocked ? status.definition.color.opacity(0.2) : CozyPalette.textSecondary.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: status.definition.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(status.isUnlocked ? status.definition.color : CozyPalette.textSecondary.opacity(0.5))
            }

            Text(status.definition.title)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(status.isUnlocked ? CozyPalette.textPrimary : CozyPalette.textSecondary)
                .multilineTextAlignment(.center)

            Text(status.definition.description)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let date = status.unlockedDate {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(status.definition.color)
            } else {
                Text("Not unlocked yet")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(CozyPalette.textSecondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .cozyCard()
        .opacity(status.isUnlocked ? 1 : 0.7)
    }
}

#Preview {
    NavigationStack {
        BadgesView()
    }
}
