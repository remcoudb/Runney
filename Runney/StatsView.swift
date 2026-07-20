import SwiftUI
import Charts

/// De twee weergaven binnen Stats. "Voortgang" = de spelscores (level/stamina/consistentie/
/// snelheid), "Loopstats" = kale, beschrijvende hardloopcijfers.
private enum StatsTab: CaseIterable {
    case progress, runStats

    var displayTitle: String {
        switch self {
        case .progress: return String(localized: "Progress", comment: "Stats tab")
        case .runStats: return String(localized: "Run Stats", comment: "Stats tab")
        }
    }
}

struct StatsView: View {
    @ObservedObject private var healthKit = HealthKitManager.shared
    @ObservedObject private var store = GameStatsStore.shared
    @AppStorage(distanceUnitStorageKey) private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue
    @State private var selectedStat: StatKind?
    @State private var selectedRun: RunWorkout?
    @State private var selectedTab: StatsTab = .progress
    @State private var showsPersonalRecords = false

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    /// Leest uit GameStatsStore i.p.v. GameEngine hier opnieuw aan te roepen — zie
    /// GameStatsStore voor waarom (o.a. weeklyTrend riep hier voorheen 8x calculate per redraw).
    private var stats: GameStats {
        store.stats
    }

    private var breakdown: GameEngineDebugInfo {
        store.breakdown
    }

    private var trend: [WeeklyTrendPoint] {
        store.trend
    }

    /// Bewust lifetimeRuns via de store, niet het rollende venster — "dit jaar", "beste maand"
    /// en "verste/snelste run ooit" moeten kloppen ongeacht hoe lang geleden dat was.
    private var runStats: RunStatsSummary {
        store.runStats
    }

    var body: some View {
        VStack(spacing: 20) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 20)
            tabPicker
                .padding(.horizontal, 20)

            TabView(selection: $selectedTab) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        progressContent
                    }
                    .padding(20)
                }
                .refreshable {
                    await healthKit.refreshAll()
                }
                .tag(StatsTab.progress)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        runStatsContent
                    }
                    .padding(20)
                }
                .refreshable {
                    await healthKit.refreshAll()
                }
                .tag(StatsTab.runStats)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .cozyBackground()
        .sheet(item: $selectedStat) { kind in
            StatDetailSheet(content: .content(for: kind, breakdown: breakdown, distanceUnit: distanceUnit))
        }
        .sheet(item: $selectedRun) { run in
            NavigationStack {
                RunDetailView(run: run)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { selectedRun = nil }
                        }
                    }
            }
        }
        .sheet(isPresented: $showsPersonalRecords) {
            PersonalRecordsView(records: store.personalRecords)
        }
    }

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            ForEach(StatsTab.allCases, id: \.self) { tab in
                Text(tab.displayTitle).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var progressContent: some View {
        levelSummary

        if let readiness = store.raceReadiness {
            RaceReadinessCard(readiness: readiness, runs: healthKit.runs)
        }

        if let plateau = store.plateauDetection {
            PlateauTipCard(plateau: plateau)
        }

        StatTrendCard(
            title: String(localized: "Stamina", comment: "Substat name"), icon: "flame.fill", color: CozyPalette.stamina,
            score: stats.stamina, points: trend, value: { $0.stamina }
        ) { selectedStat = .stamina }

        StatTrendCard(
            title: String(localized: "Consistency", comment: "Substat name"), icon: "calendar", color: CozyPalette.consistency,
            score: stats.consistency, points: trend, value: { $0.consistency }
        ) { selectedStat = .consistency }

        StatTrendCard(
            title: String(localized: "Speed", comment: "Substat name"), icon: "bolt.fill", color: CozyPalette.speed,
            score: stats.speed, points: trend, value: { $0.speed }
        ) { selectedStat = .speed }
    }

    @ViewBuilder
    private var runStatsContent: some View {
        personalRecordsCard

        let gridColumns = [GridItem(.flexible()), GridItem(.flexible())]

        LazyVGrid(columns: gridColumns, spacing: 12) {
            RunStatTile(
                icon: "calendar", color: CozyPalette.consistency,
                value: distanceUnit.format(km: runStats.weekKm, decimals: 1), label: String(localized: "This week", comment: "Run stats tile label")
            )
            RunStatTile(
                icon: "calendar.badge.clock", color: CozyPalette.consistency,
                value: distanceUnit.format(km: runStats.yearKm, decimals: 0), label: String(localized: "This year", comment: "Run stats tile label")
            )

            if let bestMonth = runStats.bestMonth {
                RunStatTile(
                    icon: "trophy.fill", color: CozyPalette.level,
                    value: distanceUnit.format(km: bestMonth.km, decimals: 1), label: String(localized: "Best month", comment: "Run stats tile label"),
                    subtitle: bestMonth.label
                )
            }

            if let longestRun = runStats.longestRun {
                RunStatTile(
                    icon: "arrow.up.right", color: CozyPalette.stamina,
                    value: distanceUnit.format(km: longestRun.distanceKm), label: String(localized: "Farthest run", comment: "Run stats tile label"),
                    subtitle: longestRun.startDate.formatted(date: .abbreviated, time: .omitted)
                ) { selectedRun = longestRun }
            }

            if let fastestRun = runStats.fastestRun {
                RunStatTile(
                    icon: "bolt.fill", color: CozyPalette.speed,
                    value: distanceUnit.formatPace(secPerKm: fastestRun.averagePaceSecPerKm), label: String(localized: "Fastest run", comment: "Run stats tile label"),
                    subtitle: fastestRun.startDate.formatted(date: .abbreviated, time: .omitted)
                ) { selectedRun = fastestRun }
            }
        }
    }

    private var personalRecordsCard: some View {
        ProGate(
            title: String(localized: "Personal Records", comment: "Pro feature title"),
            subtitle: String(localized: "Track your all-time bests automatically.", comment: "Pro feature subtitle"),
            icon: "trophy.fill"
        ) {
            Button {
                showsPersonalRecords = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(CozyPalette.speed.opacity(0.2))
                            .frame(width: 44, height: 44)
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(CozyPalette.speed)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Personal Records")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(CozyPalette.textPrimary)
                        Text("Longest run, fastest pace, best week, and more")
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

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(CozyPalette.textPrimary)
                .font(.system(size: 18, weight: .semibold))
            Text("Stats")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(CozyPalette.textPrimary)
            Spacer()
        }
        // Zelfde opzet als de Home-begroeting: rechtsboven op de header, maar dan gespiegeld
        // (via Mascot's eigen `mirrored`-optie) zodat de wasbeer richting het midden van het
        // scherm kijkt in plaats van naar de rand toe.
        .overlay(alignment: .topTrailing) {
            Mascot(pose: .greeting, height: 56, mirrored: true)
                .offset(x: -5, y: -2)
        }
        .zIndex(1)
    }

    private var levelSummary: some View {
        ProGate(
            title: String(localized: "Level & XP", comment: "Pro feature title"),
            subtitle: String(localized: "Climb through 20 levels as you run.", comment: "Pro feature subtitle"),
            icon: "star.fill"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(stats.levelTitle)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(CozyPalette.textSecondary)
                    Spacer()
                    Text("Lv. \(stats.level)")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(CozyPalette.textPrimary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(CozyPalette.level.opacity(0.25))
                        RoundedRectangle(cornerRadius: 8)
                            .fill(CozyPalette.level)
                            .frame(width: geo.size.width * stats.levelProgress)
                            .animation(.easeOut(duration: 0.6), value: stats.levelProgress)
                    }
                }
                .frame(height: 14)

                Text("\(breakdown.totalRunsFetched) runs fetched · \(stats.totalXP.formatted()) XP total")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(CozyPalette.textSecondary)
            }
            .cozyCard()
        }
    }
}

// MARK: - Loopstats-tegel

private struct RunStatTile: View {
    let icon: String
    let color: Color
    let value: String
    let label: String
    var subtitle: String?
    var onTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CozyPalette.textSecondary)
                }
            }
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(CozyPalette.textPrimary)
            Text(label)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textSecondary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(CozyPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cozyCard()
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}

// MARK: - Trend-kaart per substat

// MARK: - Plateau-tip

/// Compacte kaart die verschijnt zodra een substat de laatste weken nauwelijks bewogen heeft
/// — een gerichte suggestie i.p.v. stilzwijgend een vlakke lijn tonen.
private struct PlateauTipCard: View {
    let plateau: PlateauDetection

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(plateau.color.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(plateau.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(plateau.statLabel) has been flat for \(GameConstants.plateauDetectionWeeks) weeks")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(CozyPalette.textPrimary)
                Text(plateau.suggestion)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(CozyPalette.textSecondary)
            }
            Spacer()
        }
        .cozyCard()
    }
}

private struct StatTrendCard: View {
    let title: String
    let icon: String
    let color: Color
    let score: Int
    let points: [WeeklyTrendPoint]
    let value: (WeeklyTrendPoint) -> Int
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label {
                    Text(title)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(CozyPalette.textPrimary)
                } icon: {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                }
                Spacer()
                Text("\(score)/100")
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(color)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CozyPalette.textSecondary)
            }

            Chart(points) { point in
                AreaMark(
                    x: .value("Week", point.date),
                    y: .value("Score", value(point))
                )
                .foregroundStyle(color.opacity(0.12))
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Week", point.date),
                    y: .value("Score", value(point))
                )
                .foregroundStyle(color)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 56)

            Text("Last 8 weeks")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)
        }
        .cozyCard()
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

#Preview {
    StatsView()
}
