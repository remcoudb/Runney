import SwiftUI

struct RunsView: View {
    @ObservedObject private var healthKit = HealthKitManager.shared
    @AppStorage(distanceUnitStorageKey) private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if healthKit.isLoading && healthKit.runs.isEmpty {
                        loadingState
                    } else if let error = healthKit.lastError {
                        errorState(error)
                    } else if healthKit.runs.isEmpty {
                        emptyState
                    } else {
                        runsList
                    }
                }
                .padding(20)
            }
            .cozyBackground()
            .refreshable {
                await healthKit.refreshAll()
            }
            .navigationDestination(for: RunWorkout.self) { run in
                RunDetailView(run: run)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "map.fill")
                .foregroundStyle(CozyPalette.textPrimary)
                .font(.system(size: 18, weight: .semibold))
            Text("Runs")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(CozyPalette.textPrimary)
            Spacer()
            if !healthKit.runs.isEmpty {
                Text("\(healthKit.runs.count)")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(CozyPalette.textSecondary)
            }
        }
    }

    private var runsList: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(groupedRuns) { group in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(group.title)
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(CozyPalette.textSecondary)
                        Spacer()
                        Text(distanceUnit.format(km: group.totalKm, decimals: 1))
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(CozyPalette.stamina)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(CozyPalette.stamina.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 4)

                    VStack(spacing: 12) {
                        ForEach(group.runs) { run in
                            NavigationLink(value: run) {
                                RunRow(run: run)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// Groepeert de runs (die al aflopend op datum gesorteerd binnenkomen uit HealthKit) per
    /// maand+jaar, zonder de bestaande volgorde te verstoren — geen extra sortering nodig.
    private var groupedRuns: [RunMonthGroup] {
        var groups: [RunMonthGroup] = []
        var currentKey: DateComponents?
        var currentRuns: [RunWorkout] = []

        let calendar = Calendar.current

        for run in healthKit.runs {
            let key = calendar.dateComponents([.year, .month], from: run.startDate)
            if key != currentKey {
                if let currentKey {
                    groups.append(RunMonthGroup(components: currentKey, runs: currentRuns))
                }
                currentKey = key
                currentRuns = [run]
            } else {
                currentRuns.append(run)
            }
        }
        if let currentKey {
            groups.append(RunMonthGroup(components: currentKey, runs: currentRuns))
        }
        return groups
    }

    private var loadingState: some View {
        HStack {
            Spacer()
            VStack(spacing: 10) {
                ProgressView()
                Text("Fetching runs…")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(CozyPalette.textSecondary)
            }
            Spacer()
        }
        .padding(.top, 60)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Mascot(pose: .walking, height: 60)
                .padding(.bottom, 4)
            Text("No runs found yet")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textPrimary)
            Text("Once you have a running activity in Apple Health, it'll show up here.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Couldn't fetch runs")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textPrimary)
            Text(message)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cozyCard()
    }
}

// MARK: - Maandgroepering

private struct RunMonthGroup: Identifiable {
    let components: DateComponents
    let runs: [RunWorkout]

    var id: String { "\(components.year ?? 0)-\(components.month ?? 0)" }

    var totalKm: Double {
        runs.reduce(0) { $0 + $1.distanceKm }
    }

    /// Locale-bewuste maandnaam + jaar, bv. "Juni 2026".
    var title: String {
        guard let date = Calendar.current.date(from: components) else { return "" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: date).capitalized
    }
}

// MARK: - Losse run-rij

private struct RunRow: View {
    let run: RunWorkout
    @AppStorage(distanceUnitStorageKey) private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue
    @ObservedObject private var store = GameStatsStore.shared

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    /// True als deze exacte run ergens in de persoonlijke records staat (langste run,
    /// snelste tempo, etc.) — een leuke, directe verbinding met die aparte pagina, zodat je
    /// een record ook meteen ziet terwijl je gewoon door je runs-lijst scrolt.
    private var isPersonalRecord: Bool {
        store.personalRecords.records.contains { $0.run?.id == run.id }
    }

    /// Groen rennertje voor een gewone run, oranje bliksem/pijltjes voor tempolopen en
    /// intervaltrainingen — zo zie je in één oogopslag wat voor soort run het was, ook
    /// zonder het losse tekst-badge ernaast te hoeven lezen.
    private var icon: String {
        if run.effortType.isTempo && run.effortType.isInterval { return "bolt.horizontal.fill" }
        if run.effortType.isTempo { return "bolt.fill" }
        if run.effortType.isInterval { return "arrow.left.arrow.right" }
        return "figure.run"
    }

    private var iconColor: Color {
        (run.effortType.isTempo || run.effortType.isInterval) ? CozyPalette.speed : CozyPalette.stamina
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)

                if isPersonalRecord {
                    Circle()
                        .fill(CozyPalette.level)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.black.opacity(0.7))
                        )
                        .offset(x: 16, y: -16)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(distanceUnit.format(km: run.distanceKm))
                    Text("·")
                    Text(distanceUnit.formatPace(secPerKm: run.averagePaceSecPerKm))
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textPrimary)

                Text(run.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(CozyPalette.textSecondary)
            }

            Spacer()

            effortBadge
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CozyPalette.textSecondary)
        }
        .cozyCard()
    }

    @ViewBuilder
    private var effortBadge: some View {
        if run.effortType.isTempo || run.effortType.isInterval {
            let label = run.effortType.isTempo && run.effortType.isInterval
                ? String(localized: "Tempo + Interval", comment: "Effort type badge")
                : (run.effortType.isTempo
                    ? String(localized: "Tempo run", comment: "Effort type badge")
                    : String(localized: "Interval", comment: "Effort type badge"))

            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.speed)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(CozyPalette.speed.opacity(0.15))
                .clipShape(Capsule())
        }
    }
}

#Preview {
    RunsView()
}
