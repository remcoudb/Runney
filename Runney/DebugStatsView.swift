import SwiftUI

/// Tijdelijk testscherm: toont niet alleen de eindscores, maar ook alle tussenliggende
/// getallen zodat je kunt checken of de logica klopt met je eigen loopgeschiedenis.
/// Vervang dit later door de echte, gepolijste Stats-pagina.
struct DebugStatsView: View {
    @ObservedObject private var healthKit = HealthKitManager.shared
    @ObservedObject private var store = GameStatsStore.shared

    private var breakdown: GameEngineDebugInfo {
        store.breakdown
    }

    var body: some View {
        NavigationStack {
            List {
                if healthKit.isLoading {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Runs ophalen uit HealthKit…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let error = healthKit.lastError {
                    Section("Fout") {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                Section("Algemeen") {
                    LabeledContent("Runs opgehaald", value: "\(breakdown.totalRunsFetched)")
                    LabeledContent("App geïnstalleerd op", value: breakdown.appInstallDate.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Runs die meetellen voor XP", value: "\(breakdown.xpEligibleRunCount) / \(breakdown.totalRunsFetched)")
                    LabeledContent("Level", value: "\(breakdown.stats.level) — \(breakdown.stats.levelTitle)")
                    LabeledContent("Totaal XP", value: "\(breakdown.stats.totalXP)")
                    LabeledContent("XP in huidig level", value: "\(breakdown.stats.xpIntoCurrentLevel) / \(breakdown.stats.xpNeededForNextLevel)")
                }

                Section("Stamina — \(breakdown.stats.stamina)/100") {
                    LabeledContent("Effectief weekvolume", value: kmString(breakdown.effectiveStaminaVolumeKm))
                    ForEach(breakdown.recentWeeks) { week in
                        LabeledContent(weekLabel(week.weeksAgo), value: "\(kmString(week.km)) · \(week.runCount)x")
                    }
                }

                Section("Consistentie — \(breakdown.stats.consistency)/100") {
                    LabeledContent("Runs deze week", value: "\(breakdown.runsThisWeek)")
                    LabeledContent("Streak", value: "\(breakdown.streakWeeks) \(breakdown.streakWeeks == 1 ? "week" : "weken")")
                }

                Section("Snelheid — \(breakdown.stats.speed)/100") {
                    LabeledContent("Snelste kwalificerende tempo", value: paceString(breakdown.fastestQualifyingPaceSecPerKm))
                    LabeledContent("Tempoloop laatste 7 dagen", value: breakdown.hasTempoRunLast7Days ? "Ja" : "Nee")
                    LabeledContent("Interval laatste 7 dagen", value: breakdown.hasIntervalRunLast7Days ? "Ja" : "Nee")
                }

                Section("Losse runs (recentste eerst)") {
                    ForEach(healthKit.runs) { run in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(run.startDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline.weight(.medium))
                            Text("\(String(format: "%.2f", run.distanceKm)) km · \(paceString(run.averagePaceSecPerKm))\(effortLabel(run.effortType))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Debug: Stats")
            .refreshable {
                await healthKit.fetchRuns()
            }
        }
    }

    private func kmString(_ km: Double) -> String {
        String(format: "%.1f km", km)
    }

    private func paceString(_ paceSecPerKm: Double?) -> String {
        guard let pace = paceSecPerKm, pace > 0 else { return "-" }
        let minutes = Int(pace) / 60
        let seconds = Int(pace) % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }

    private func weekLabel(_ weeksAgo: Int) -> String {
        guard weeksAgo > 0 else { return "Deze week" }
        return "\(weeksAgo) \(weeksAgo == 1 ? "week" : "weken") terug"
    }

    private func effortLabel(_ effort: RunEffortType) -> String {
        if effort.isTempo && effort.isInterval { return " · tempo + interval" }
        if effort.isTempo { return " · tempoloop" }
        if effort.isInterval { return " · interval" }
        return ""
    }
}

#Preview {
    DebugStatsView()
}
