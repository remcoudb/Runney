import SwiftUI

/// Gedeeld tussen HomeView (leest 'm om de levelkaart/level-up-viering te tonen of niet) en
/// ProfileView (de toggle om 'm aan/uit te zetten) — één centrale sleutel i.p.v. de string
/// los op twee plekken te herhalen.
let showsLevelOnHomeStorageKey = "showsLevelOnHome"

struct HomeView: View {
    @ObservedObject private var healthKit = HealthKitManager.shared
    @ObservedObject private var store = GameStatsStore.shared
    @ObservedObject private var plannedRunStore = PlannedRunStore.shared
    @ObservedObject private var subscriptions = SubscriptionManager.shared
    /// Standaard aan — dit is een opt-out voor wie liever geen level-gerichte gamification
    /// op Home ziet, geen opt-in die de meeste mensen eerst zouden moeten vinden en aanzetten.
    @AppStorage(showsLevelOnHomeStorageKey) private var showsLevelOnHome: Bool = true
    /// Gedeeld met ProfileView via UserDefaults — wijzig je 'm daar, dan update dit hier automatisch mee.
    @AppStorage("userName") private var userName: String = "Runner"
    /// 0 = "nog nooit bijgehouden". Zo vieren we geen valse level-up de allereerste keer
    /// dat deze feature draait, ook niet voor bestaande testers die al een hoog level hadden.
    @AppStorage("lastSeenLevel") private var lastSeenLevel: Int = 0
    /// -1 = "nog nooit bijgehouden". Bewust een hoogwatermerk (het hoogste mijlpaal dat ooit
    /// al gevierd is) i.p.v. de kale streak-stand van de vorige check op te slaan — die kale
    /// stand kan namelijk tijdelijk dippen (bv. aan het begin van een nieuwe week, vóórdat je
    /// die week alweer gelopen hebt), en zonder dit hoogwatermerk zou zo'n dip een al gevierd
    /// mijlpaal ten onrechte weer als "nieuw" laten voelen zodra de streak weer oploopt.
    @AppStorage("highestCelebratedStreakMilestone") private var highestCelebratedStreakMilestone: Int = -1
    /// Komma-gescheiden lijst van badge-ID's die al eens getoond zijn (behaald én geen valse
    /// viering meer waard). Simpele opslag i.p.v. een Set, want @AppStorage kent geen Set<String>.
    @AppStorage("unlockedBadgeIDs") private var unlockedBadgeIDsRaw: String = ""
    /// Zorgt dat we bij de allereerste keer alle dan al behaalde badges als baseline zetten,
    /// i.p.v. ze meteen allemaal achter elkaar te vieren.
    @AppStorage("hasInitializedBadgeTracking") private var hasInitializedBadgeTracking: Bool = false
    /// JSON-gecodeerde [String: Double] met per record-id de laatst geziene metricValue —
    /// nodig omdat @AppStorage geen Dictionary rechtstreeks ondersteunt. Gebruikt om een
    /// "verbeterd record"-viering te herkennen zonder de score zelf ergens dubbel op te slaan.
    @AppStorage("personalRecordBaseline") private var personalRecordBaselineData: Data = Data()
    /// Zelfde principe als hasInitializedBadgeTracking: voorkomt dat bij de allereerste keer
    /// dat deze feature draait, meteen alle bestaande records achter elkaar gevierd worden.
    @AppStorage("hasInitializedRecordTracking") private var hasInitializedRecordTracking: Bool = false
    @AppStorage(distanceUnitStorageKey) private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue
    @State private var selectedStat: StatKind?
    @State private var showsFormDetail = false
    @State private var celebration: CelebrationTrigger?
    @State private var selectedRun: RunWorkout?
    @State private var recapRun: RunWorkout?
    @State private var showsPlannedRunDetail = false

    /// Leest uit GameStatsStore, die dit maar één keer per data-wijziging berekent i.p.v.
    /// bij elke redraw — zie GameStatsStore voor waarom dat nodig was.
    private var stats: GameStats {
        store.stats
    }

    private var breakdown: GameEngineDebugInfo {
        store.breakdown
    }

    private var todaySummary: TodaySummary {
        store.todaySummary
    }

    private var weeklyRecap: WeeklyRecap {
        store.weeklyRecap
    }

    /// nil als er geen geplande run voor vandaag is — dan blijft de kaart gewoon weg.
    private var todaysPlanComparison: PlannedRunComparison? {
        guard let plannedRun = plannedRunStore.plannedRun(for: Date()) else { return nil }
        return plannedRun.comparison(against: healthKit.runs)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GreetingHeader(name: userName.isEmpty ? "Runner" : userName)
                ProGate(
                    title: String(localized: "Level & XP", comment: "Pro feature title"),
                    subtitle: String(localized: "Climb through 20 levels as you run.", comment: "Pro feature subtitle"),
                    icon: "star.fill"
                ) {
                    if showsLevelOnHome {
                        LevelCard(stats: stats, forecast: store.levelForecast)
                            .onTapGesture { selectedStat = .level }
                    }
                }
                if let readiness = store.raceReadiness {
                    RaceReadinessCompactBanner(readiness: readiness, runs: healthKit.runs)
                }
                if let comparison = todaysPlanComparison {
                    TodayPlanCard(comparison: comparison)
                        .onTapGesture {
                            if let matchedRun = comparison.matchedRun {
                                recapRun = matchedRun
                            } else {
                                showsPlannedRunDetail = true
                            }
                        }
                }
                StatsCard(stats: stats, onSelect: { selectedStat = $0 }, onFormTap: { showsFormDetail = true })
                TodayWeekWidgets(todaySummary: todaySummary, weeklyRecap: weeklyRecap, onSelectRun: { selectedRun = $0 })
            }
            .padding(20)
        }
        .cozyBackground()
        .task {
            await healthKit.setupAndFetch()
            checkForCelebrations()
        }
        .refreshable {
            await healthKit.refreshAll()
            checkForCelebrations()
        }
        // Bewust de hele `stats`-waarde i.p.v. alleen `stats.level`: GameStatsStore rekent
        // sinds de main-thread-fix asynchroon (Task.detached), dus de eerste, directe
        // aanroep hierboven kan op een moment vallen vóórdat badges/records/breakdown vers
        // binnen zijn. Zodra de store daadwerkelijk klaar is, verandert `stats` (bijna)
        // altijd mee — en dán pas is een betrouwbare check mogelijk. Dit voorkomt dat een
        // badge die op het racy moment nét gemist werd, bij een volgend bezoek alsnog
        // (opnieuw) lijkt te "verschijnen".
        .onChange(of: stats) { _, _ in
            checkForCelebrations()
        }
        .sheet(item: $selectedStat) { kind in
            StatDetailSheet(content: detailContent(for: kind))
        }
        .sheet(isPresented: $showsFormDetail) {
            CurrentFormDetailSheet(stats: stats)
        }
        .sheet(isPresented: $showsPlannedRunDetail) {
            if let comparison = todaysPlanComparison {
                PlannedRunDetailView(comparison: comparison)
            }
        }
        .fullScreenCover(item: $celebration) { trigger in
            CelebrationView(trigger: trigger) {
                celebration = nil
            }
        }
        .fullScreenCover(item: $recapRun) { run in
            RunRecapView(
                run: run,
                allRuns: healthKit.runs,
                planComparison: plannedRunStore.plannedRun(for: run.startDate)?.comparison(against: healthKit.runs),
                raceGoal: store.raceGoal
            )
        }
        .sheet(item: $selectedRun) { run in
            NavigationStack {
                RunDetailView(run: run)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Sluiten") { selectedRun = nil }
                        }
                    }
            }
        }
    }

    private func detailContent(for kind: StatKind) -> StatDetailContent {
        .content(for: kind, breakdown: breakdown, distanceUnit: DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers)
    }

    /// Checkt op alle bekende vieringstriggers. Bij meerdere gelijktijdig (zeldzaam, bv. een
    /// run die zowel een level als een badge oplevert) krijgt level-up voorrang — er kan maar
    /// één viering tegelijk getoond worden.
    private func checkForCelebrations() {
        if let levelUp = checkForLevelUp() {
            celebration = levelUp
            return
        }
        if let badge = checkForNewBadges() {
            celebration = badge
            return
        }
        if let record = checkForNewPersonalRecord() {
            celebration = record
            return
        }
        if let streak = checkForStreakMilestone() {
            celebration = streak
        }
    }

    private func checkForLevelUp() -> CelebrationTrigger? {
        // Bewust geen "Level omhoog!"-viering als de levelweergave uitstaat, óf zonder
        // Pro-abonnement — dat zou tegenstrijdig aanvoelen voor iets dat je toch niet kunt
        // bekijken. lastSeenLevel blijft ondertussen wél gewoon bijgewerkt, zodat er geen
        // opgespaarde "gemiste" level-ups alsnog verschijnen zodra dit weer beschikbaar wordt.
        guard showsLevelOnHome && subscriptions.isPro else {
            lastSeenLevel = stats.level
            return nil
        }

        let currentLevel = stats.level

        guard lastSeenLevel != 0 else {
            // Eerste keer dat we dit bijhouden — baseline zetten, niet meteen vieren.
            lastSeenLevel = currentLevel
            return nil
        }

        guard currentLevel > lastSeenLevel else { return nil }
        lastSeenLevel = currentLevel
        return .levelUp(stats)
    }

    private func checkForNewBadges() -> CelebrationTrigger? {
        var seen = Set(unlockedBadgeIDsRaw.split(separator: ",").map(String.init))

        // Zonder Pro (of vóór de eerste initialisatie) alles wat al behaald is stilletjes als
        // baseline bijwerken — geen viering, en geen opgespaarde vieringen die alsnog
        // achter elkaar afgaan zodra er een abonnement wordt afgesloten.
        guard hasInitializedBadgeTracking && subscriptions.isPro else {
            for status in store.badgeStatuses where status.isUnlocked {
                seen.insert(status.definition.id)
            }
            unlockedBadgeIDsRaw = seen.sorted().joined(separator: ",")
            hasInitializedBadgeTracking = true
            return nil
        }

        for status in store.badgeStatuses {
            guard !seen.contains(status.definition.id) else { continue }
            guard status.isUnlocked else { continue }
            seen.insert(status.definition.id)
            unlockedBadgeIDsRaw = seen.sorted().joined(separator: ",")
            return .badge(status.definition)
        }
        return nil
    }

    /// Vergelijkt elk persoonlijk record met de laatst bekende waarde. Zodra één record
    /// verbeterd is, vieren we die ene en laten de rest staan voor een volgende check-ronde —
    /// zelfde "één viering per keer"-principe als checkForNewBadges hierboven.
    private func checkForNewPersonalRecord() -> CelebrationTrigger? {
        var baseline = decodePersonalRecordBaseline()

        guard hasInitializedRecordTracking && subscriptions.isPro else {
            for record in store.personalRecords.records {
                baseline[record.id] = record.metricValue
            }
            savePersonalRecordBaseline(baseline)
            hasInitializedRecordTracking = true
            return nil
        }

        for record in store.personalRecords.records {
            guard let previous = baseline[record.id] else {
                // Nieuw type record dat er nog niet eerder was (bv. de eerste run ooit binnen
                // de 10K-afstandsband) — baseline zetten, niet meteen vieren.
                baseline[record.id] = record.metricValue
                continue
            }

            let improved = record.isHigherBetter ? record.metricValue > previous : record.metricValue < previous
            guard improved else { continue }

            baseline[record.id] = record.metricValue
            savePersonalRecordBaseline(baseline)
            return .personalRecord(record)
        }

        savePersonalRecordBaseline(baseline)
        return nil
    }

    private func decodePersonalRecordBaseline() -> [String: Double] {
        (try? JSONDecoder().decode([String: Double].self, from: personalRecordBaselineData)) ?? [:]
    }

    private func savePersonalRecordBaseline(_ baseline: [String: Double]) {
        personalRecordBaselineData = (try? JSONEncoder().encode(baseline)) ?? Data()
    }

    private func checkForStreakMilestone() -> CelebrationTrigger? {
        let currentStreak = breakdown.streakWeeks
        let currentMilestone = GameEngine.highestStreakMilestone(for: currentStreak)

        guard highestCelebratedStreakMilestone != -1 else {
            // Eerste keer dat we dit bijhouden — baseline zetten op wat nu al gehaald is,
            // niet meteen vieren voor iets dat allang bereikt was.
            highestCelebratedStreakMilestone = currentMilestone ?? 0
            return nil
        }

        // Alleen vieren als het huidige mijlpaal daadwerkelijk HOGER is dan het hoogste dat
        // ooit al gevierd is — een tijdelijke dip in de streak zelf (bv. begin van een nieuwe
        // week) kan dit getal dus nooit terugzetten, waardoor hetzelfde mijlpaal ook nooit
        // een tweede keer als "nieuw" kan overkomen.
        guard let currentMilestone, currentMilestone > highestCelebratedStreakMilestone else { return nil }
        highestCelebratedStreakMilestone = currentMilestone
        return .streakMilestone(weeks: currentMilestone)
    }
}

// MARK: - Greeting header

private struct GreetingHeader: View {
    let name: String

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return String(localized: "Good morning", comment: "Time-of-day greeting")
        case 12..<18: return String(localized: "Good afternoon", comment: "Time-of-day greeting")
        default: return String(localized: "Good evening", comment: "Time-of-day greeting")
        }
    }

    var body: some View {
        Text("\(greeting), \(name)")
            .font(.system(.title2, design: .rounded, weight: .bold))
            .foregroundStyle(CozyPalette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
            // Zit "bovenop" de begroetingsregel, rechtsboven — zit hier binnen de
            // scrollbare VStack (niet als vaste overlay op de ScrollView zelf), dus
            // beweegt gewoon mee omhoog/omlaag met de rest van de inhoud bij het scrollen.
            .overlay(alignment: .topLeading) {
                Mascot(pose: .greeting, height: 56)
                    .offset(x: 5, y: -2)
            }
            // Moet hier, op dit hele blok, staan — niet op de Image zelf hierboven. Zonder
            // dit tekent de kaart die in de VStack ná GreetingHeader komt (bv. LevelCard)
            // gewoon overheen, want SwiftUI tekent VStack-elementen in volgorde van
            // declaratie, en GreetingHeader staat als eerste.
            .zIndex(1)
    }
}

// MARK: - Level card

private struct LevelCard: View {
    let stats: GameStats
    let forecast: LevelForecast

    private var remainingXPText: String {
        guard stats.xpNeededForNextLevel > 0 else {
            return String(localized: "Highest level reached", comment: "Shown when max level is reached")
        }
        let remaining = stats.xpNeededForNextLevel - stats.xpIntoCurrentLevel
        return "\(remaining.formatted()) XP to Lv. \(stats.level + 1)"
    }

    /// nil zolang er geen zinvolle voorspelling te maken is (net begonnen, of stilstand in
    /// XP-opbouw) — dan tonen we gewoon geen regel i.p.v. een onzinnige "oneindig"-tekst.
    private var forecastText: String? {
        guard let weeks = forecast.estimatedWeeks else { return nil }
        let weekWord = weeks == 1 ? String(localized: "week", comment: "Singular") : String(localized: "weeks", comment: "Plural")
        return "~\(weeks) \(weekWord) to Lv. \(stats.level + 1) at this rate"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stats.levelTitle)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(CozyPalette.textPrimary)
                    Text(remainingXPText)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(CozyPalette.textSecondary)
                }

                Spacer()

                Text("Lv. \(stats.level)")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(CozyPalette.level)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(CozyPalette.level.opacity(0.2))
                    .clipShape(Capsule())
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(CozyPalette.level.opacity(0.25))
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [CozyPalette.level, CozyPalette.speed],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * stats.levelProgress)
                        .animation(.easeOut(duration: 0.6), value: stats.levelProgress)
                }
            }
            .frame(height: 14)

            if let forecastText {
                Text(forecastText)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(CozyPalette.textSecondary)
            }
        }
        .cozyCard()
    }
}

// MARK: - Huidige vorm

/// Vaste bron van waarheid voor de vorm-niveaus — gebruikt door zowel StatsCard (welk
/// label/kleur nu geldt) als CurrentFormDetailSheet (de volledige lijst met bereiken),
/// zodat de drempels maar op één plek staan.
private struct FormTier: Identifiable {
    let id: Int
    let range: ClosedRange<Int>
    let label: String
    /// Kleur loopt bewust door het hele palet heen naarmate de vorm beter wordt — zo voelt
    /// vooruitgang letterlijk aan als "meer van de kleuren van de app te pakken hebben".
    let color: Color

    var rangeText: String { "\(range.lowerBound)-\(range.upperBound)" }

    static let all: [FormTier] = [
        FormTier(id: 0, range: 0...19, label: String(localized: "Just starting", comment: "Current form tier label"), color: CozyPalette.textSecondary),
        FormTier(id: 1, range: 20...39, label: String(localized: "Building up", comment: "Current form tier label"), color: CozyPalette.stamina),
        FormTier(id: 2, range: 40...59, label: String(localized: "Solid form", comment: "Current form tier label"), color: CozyPalette.consistency),
        FormTier(id: 3, range: 60...79, label: String(localized: "Strong form", comment: "Current form tier label"), color: CozyPalette.speed),
        FormTier(id: 4, range: 80...100, label: String(localized: "Peak form", comment: "Current form tier label"), color: CozyPalette.level)
    ]

    static func current(for score: Int) -> FormTier {
        all.first { $0.range.contains(score) } ?? all[0]
    }
}

/// Detailscherm dat uitlegt hoe "Huidige vorm" is opgebouwd (gemiddelde van de drie substats)
/// en welke niveaus er zijn — zelfde visuele taal als StatDetailSheet, maar met een niveau-
/// lijst i.p.v. tips, want daar draait dit scherm om.
private struct CurrentFormDetailSheet: View {
    let stats: GameStats
    @Environment(\.dismiss) private var dismiss

    private var overallForm: Int {
        (stats.stamina + stats.consistency + stats.speed) / 3
    }

    private var currentTier: FormTier {
        FormTier.current(for: overallForm)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                Text("Current form is the average of your Stamina, Consistency, and Speed scores — a quick overall picture of where you stand right now.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(CozyPalette.textPrimary)

                componentBreakdown

                sectionTitle("Levels")
                VStack(spacing: 0) {
                    ForEach(Array(FormTier.all.enumerated()), id: \.element.id) { index, tier in
                        if index > 0 {
                            Divider().opacity(0.5)
                        }
                        tierRow(tier)
                    }
                }
                .padding(.horizontal, 16)
                .background(CozyPalette.background)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                doneButton
            }
            .padding(20)
        }
        .background(CozyPalette.cardBackground.ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(currentTier.color.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: "chart.pie.fill")
                        .foregroundStyle(currentTier.color)
                        .font(.system(size: 18, weight: .semibold))
                }
                Text("Current form")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(CozyPalette.textPrimary)
            }
            Spacer()
            Text("\(overallForm)/100")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(currentTier.color)
        }
    }

    private var componentBreakdown: some View {
        VStack(spacing: 10) {
            componentRow(label: String(localized: "Stamina", comment: "Substat name"), value: stats.stamina, color: CozyPalette.stamina)
            componentRow(label: String(localized: "Consistency", comment: "Substat name"), value: stats.consistency, color: CozyPalette.consistency)
            componentRow(label: String(localized: "Speed", comment: "Substat name"), value: stats.speed, color: CozyPalette.speed)
        }
        .padding(16)
        .background(CozyPalette.background)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func componentRow(label: String, value: Int, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(CozyPalette.textPrimary)
            Spacer()
            Text("\(value)/100")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    private func tierRow(_ tier: FormTier) -> some View {
        let isCurrent = tier.id == currentTier.id
        return HStack(spacing: 10) {
            Circle()
                .fill(tier.color)
                .frame(width: 10, height: 10)
            Text(tier.label)
                .font(.system(.body, design: .rounded, weight: isCurrent ? .bold : .regular))
                .foregroundStyle(isCurrent ? CozyPalette.textPrimary : CozyPalette.textSecondary)
            Spacer()
            Text(tier.rangeText)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textSecondary)
            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tier.color)
            }
        }
        .padding(.vertical, 10)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(CozyPalette.textPrimary)
    }

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Done")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.primaryButtonText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(CozyPalette.primaryButtonBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.top, 8)
    }
}

// MARK: - Stats card (stamina / consistentie / speed)

private struct StatsCard: View {
    let stats: GameStats
    let onSelect: (StatKind) -> Void
    let onFormTap: () -> Void

    private var overallForm: Int {
        (stats.stamina + stats.consistency + stats.speed) / 3
    }

    private var currentTier: FormTier {
        FormTier.current(for: overallForm)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            formHeader
            StatBarRow(label: String(localized: "Stamina", comment: "Substat name"), value: stats.stamina, color: CozyPalette.stamina, icon: "flame.fill")
                .onTapGesture { onSelect(.stamina) }
            StatBarRow(label: String(localized: "Consistency", comment: "Substat name"), value: stats.consistency, color: CozyPalette.consistency, icon: "calendar")
                .onTapGesture { onSelect(.consistency) }
            StatBarRow(label: String(localized: "Speed", comment: "Substat name"), value: stats.speed, color: CozyPalette.speed, icon: "bolt.fill")
                .onTapGesture { onSelect(.speed) }
        }
        .cozyCard()
    }

    /// Voorheen een aparte sectie ("Huidige vorm") vóór deze kaart — nu de kop van de kaart
    /// zelf, want het label is toch al letterlijk het gemiddelde van de drie balken eronder.
    private var formHeader: some View {
        HStack(spacing: 8) {
            Text("Current form")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(CozyPalette.textSecondary)
            Rectangle()
                .fill(CozyPalette.textSecondary.opacity(0.25))
                .frame(height: 1)
            Text(currentTier.label)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(currentTier.color)
        }
        .contentShape(Rectangle())
        .onTapGesture { onFormTap() }
    }
}

private struct StatBarRow: View {
    let label: String
    let value: Int
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label {
                    Text(label)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(CozyPalette.textPrimary)
                } icon: {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                }
                Spacer()
                Text("\(value)/100")
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.2))
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(value) / 100)
                        .animation(.easeOut(duration: 0.6), value: value)

                    // Referentiestreepjes op 25/50/75% zodat meteen duidelijk is hoe ver
                    // de balk richting het maximum van 100 staat.
                    ForEach([0.25, 0.5, 0.75], id: \.self) { fraction in
                        Rectangle()
                            .fill(Color.black.opacity(0.12))
                            .frame(width: 1)
                            .offset(x: geo.size.width * fraction)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(height: 14)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Today card

// MARK: - Vandaag / Deze week (samengevoegd met tabjes)

/// Combineert de vroegere losse TodayCard/WeekCard-kaarten tot één kaart met een tabje
/// erboven — scheelt een hele kop + kaart t.o.v. twee losse secties, terwijl beide
/// invalshoeken (dag/week) nog steeds één tik verwijderd zijn.
/// Compacte kaart op Home die laat zien wat er vandaag gepland staat (uit PlannedRunStore),
/// en — zodra er een matchende run is — hoe dicht dat bij het doel zat. Verschijnt alleen
/// als er daadwerkelijk een geplande run voor vandaag is; zie HomeView.todaysPlanComparison.
private struct TodayPlanCard: View {
    let comparison: PlannedRunComparison
    @AppStorage(distanceUnitStorageKey) private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    private var plannedRun: PlannedRun { comparison.plannedRun }

    private var paceText: String {
        if let max = plannedRun.targetPaceMaxSecPerKm {
            return "\(distanceUnit.formatPace(secPerKm: plannedRun.targetPaceSecPerKm))–\(distanceUnit.formatPace(secPerKm: max))"
        }
        return distanceUnit.formatPace(secPerKm: plannedRun.targetPaceSecPerKm)
    }

    private var statusBadge: (text: String, color: Color)? {
        switch comparison.status {
        case .upcoming: return nil
        case .missed: return nil
        case .onTarget: return (String(localized: "On target", comment: "Today's plan status badge"), CozyPalette.stamina)
        case .offTarget: return (String(localized: "Off target", comment: "Today's plan status badge"), CozyPalette.speed)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(CozyPalette.consistency.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(CozyPalette.consistency)
                    .font(.system(size: 18, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Today's plan: \(plannedRun.label)")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(CozyPalette.textPrimary)
                Text("\(distanceUnit.format(km: plannedRun.distanceKm, decimals: 1)) · \(paceText)")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(CozyPalette.textSecondary)
            }

            Spacer()

            if let badge = statusBadge {
                Text(badge.text)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(badge.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(badge.color.opacity(0.15))
                    .clipShape(Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CozyPalette.textSecondary)
        }
        .cozyCard()
    }
}

private struct TodayWeekWidgets: View {
    let todaySummary: TodaySummary
    let weeklyRecap: WeeklyRecap
    let onSelectRun: (RunWorkout) -> Void

    @AppStorage(distanceUnitStorageKey) private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue
    @State private var showsTodayDetail = false
    @State private var showsWeekDetail = false

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    var body: some View {
        HStack(spacing: 12) {
            TodayWidget(todaySummary: todaySummary, distanceUnit: distanceUnit)
                .onTapGesture { showsTodayDetail = true }

            WeekWidget(weeklyRecap: weeklyRecap, distanceUnit: distanceUnit)
                .onTapGesture { showsWeekDetail = true }
        }
        .sheet(isPresented: $showsTodayDetail) {
            TodayDetailSheet(todaySummary: todaySummary, onSelectRun: { run in
                showsTodayDetail = false
                onSelectRun(run)
            })
        }
        .sheet(isPresented: $showsWeekDetail) {
            WeekDetailSheet(weeklyRecap: weeklyRecap)
        }
    }
}

/// Compacte tegel: alleen het essentiële getal, tikken opent het volledige popup-scherm
/// (zie TodayDetailSheet) — hield Home eerder onnodig druk met alles in één grote kaart.
private struct TodayWidget: View {
    let todaySummary: TodaySummary
    let distanceUnit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "figure.run")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CozyPalette.stamina)
                Text("Today")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(CozyPalette.textSecondary)
            }

            if todaySummary.hasRunToday {
                Text(distanceUnit.format(km: todaySummary.totalDistanceKm))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(CozyPalette.textPrimary)
                if let firstRun = todaySummary.todaysRuns.first {
                    Text(distanceUnit.formatPace(secPerKm: firstRun.averagePaceSecPerKm))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(CozyPalette.textSecondary)
                }
            } else {
                Text("No run yet")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(CozyPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cozyCard()
    }
}

private struct WeekWidget: View {
    let weeklyRecap: WeeklyRecap
    let distanceUnit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CozyPalette.consistency)
                Text("This week")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(CozyPalette.textSecondary)
            }

            if weeklyRecap.hasRunThisWeek {
                Text("\(weeklyRecap.runCount) \(weeklyRecap.runCount == 1 ? String(localized: "run", comment: "Singular") : String(localized: "runs", comment: "Plural"))")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(CozyPalette.textPrimary)
                Text(distanceUnit.format(km: weeklyRecap.totalDistanceKm, decimals: 1))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(CozyPalette.textSecondary)
            } else {
                Text("No runs yet")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(CozyPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cozyCard()
    }
}

/// Popup voor de "Vandaag"-tegel — bevat exact de inhoud die voorheen in de tabbladkaart zat.
private struct TodayDetailSheet: View {
    let todaySummary: TodaySummary
    let onSelectRun: (RunWorkout) -> Void

    @AppStorage(distanceUnitStorageKey) private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue
    @ObservedObject private var healthKit = HealthKitManager.shared
    @ObservedObject private var plannedRunStore = PlannedRunStore.shared
    @ObservedObject private var store = GameStatsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var recapRun: RunWorkout?

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if todaySummary.hasRunToday {
                        todayRunsList
                        Divider().opacity(0.5)
                        todayDeltas
                    } else {
                        Text("No run yet today — time to give your stamina a boost?")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(CozyPalette.textSecondary)
                    }
                }
                .padding(20)
            }
            .cozyBackground()
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .fullScreenCover(item: $recapRun) { run in
            RunRecapView(
                run: run,
                allRuns: healthKit.runs,
                planComparison: plannedRunStore.plannedRun(for: run.startDate)?.comparison(against: healthKit.runs),
                raceGoal: store.raceGoal
            )
        }
    }

    private var todayRunsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(todaySummary.todaysRuns) { run in
                HStack(spacing: 8) {
                    Button {
                        onSelectRun(run)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "figure.run")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(CozyPalette.stamina)
                            Text(distanceUnit.format(km: run.distanceKm))
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(CozyPalette.textPrimary)
                            Text("· \(distanceUnit.formatPace(secPerKm: run.averagePaceSecPerKm))")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(CozyPalette.textSecondary)
                            Spacer()
                            todayEffortBadge(for: run)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CozyPalette.textSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Bewust een losse, naast-elkaar-staande Button i.p.v. genest binnen de
                    // rij hierboven — een Button binnen een view die zelf ook .onTapGesture
                    // heeft, geeft in SwiftUI onvoorspelbaar gedrag (de buitenste tik "slokt"
                    // de binnenste vaak op). Twee losse Buttons naast elkaar werkt wél altijd
                    // betrouwbaar.
                    Button {
                        recapRun = run
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CozyPalette.level)
                            .padding(6)
                            .background(CozyPalette.level.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func todayEffortBadge(for run: RunWorkout) -> some View {
        if run.effortType.isTempo || run.effortType.isInterval {
            let label = run.effortType.isTempo
                ? String(localized: "Tempo run", comment: "Effort type badge")
                : String(localized: "Interval", comment: "Effort type badge")
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.speed)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(CozyPalette.speed.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    private var todayDeltas: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            WeekDeltaChip(icon: "flame.fill", color: CozyPalette.stamina, delta: todaySummary.staminaDelta)
            WeekDeltaChip(icon: "calendar", color: CozyPalette.consistency, delta: todaySummary.consistencyDelta)
            WeekDeltaChip(icon: "bolt.fill", color: CozyPalette.speed, delta: todaySummary.speedDelta)
            WeekDeltaChip(icon: "star.fill", color: CozyPalette.level, delta: todaySummary.xpGained)
        }
    }
}

/// Popup voor de "Deze week"-tegel — bevat exact de inhoud die voorheen in de tabbladkaart zat.
private struct WeekDetailSheet: View {
    let weeklyRecap: WeeklyRecap

    @AppStorage(distanceUnitStorageKey) private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue
    @AppStorage(showsLevelOnHomeStorageKey) private var showsLevelOnHome: Bool = true
    @ObservedObject private var subscriptions = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    weekStrip

                    if weeklyRecap.hasRunThisWeek {
                        weekSummaryLine
                        Divider().opacity(0.5)
                        weekDeltaGrid
                    } else {
                        Text("No runs yet this week — a good moment to get started!")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(CozyPalette.textSecondary)
                    }
                }
                .padding(20)
            }
            .cozyBackground()
            .navigationTitle("This week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var weekStrip: some View {
        HStack(spacing: 8) {
            ForEach(weeklyRecap.dayStatuses) { status in
                WeekDayDot(status: status)
            }
        }
    }

    private var weekSummaryLine: some View {
        HStack(spacing: 8) {
            Text("\(weeklyRecap.runCount) \(weeklyRecap.runCount == 1 ? String(localized: "run", comment: "Singular") : String(localized: "runs", comment: "Plural"))")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textPrimary)
            Text("· \(distanceUnit.format(km: weeklyRecap.totalDistanceKm, decimals: 1))")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)

            Spacer()

            if showsLevelOnHome && subscriptions.isPro && weeklyRecap.didLevelUp {
                Text("Lv. \(weeklyRecap.levelAtWeekStart) → \(weeklyRecap.levelNow)")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(CozyPalette.level)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(CozyPalette.level.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }

    private var weekDeltaGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            WeekDeltaChip(icon: "flame.fill", color: CozyPalette.stamina, delta: weeklyRecap.staminaDelta)
            WeekDeltaChip(icon: "calendar", color: CozyPalette.consistency, delta: weeklyRecap.consistencyDelta)
            WeekDeltaChip(icon: "bolt.fill", color: CozyPalette.speed, delta: weeklyRecap.speedDelta)
            WeekDeltaChip(icon: "star.fill", color: CozyPalette.level, delta: weeklyRecap.xpGained)
        }
    }
}

/// Eén bolletje in de weekstrip: gevuld als er die dag gelopen is, met een dun randje om
/// vandaag (los van of er al gelopen is — dat kan allebei tegelijk gelden).
private struct WeekDayDot: View {
    let status: WeekDayStatus

    var body: some View {
        VStack(spacing: 6) {
            Circle()
                .fill(status.hasRun ? CozyPalette.stamina : CozyPalette.textSecondary.opacity(0.12))
                .frame(width: 30, height: 30)
                .overlay(
                    Circle()
                        .stroke(CozyPalette.speed, lineWidth: status.isToday ? 2 : 0)
                        .padding(-2)
                )
            Text(status.label)
                .font(.system(.caption2, design: .rounded, weight: status.isToday ? .semibold : .regular))
                .foregroundStyle(status.isToday ? CozyPalette.speed : CozyPalette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Compacte delta-chip, gedeeld door "Vandaag" en "Deze week": "+7" als gevulde,
/// kleur-getinte capsule — twee per rij naast elkaar in een 2×2-grid.
private struct WeekDeltaChip: View {
    let icon: String
    let color: Color
    let delta: Int

    private var deltaText: String {
        if delta > 0 { return "+\(delta)" }
        if delta < 0 { return "\(delta)" }
        return "±0"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
            Text(deltaText)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    HomeView()
}
