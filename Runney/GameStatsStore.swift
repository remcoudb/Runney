import Foundation
import Combine

/// Cachet alle afgeleide GameEngine-resultaten (scores, debug-breakdown, trend, dagsamenvatting,
/// loopstats, badges) op één centrale plek, en herberekent ze alleen wanneer de onderliggende
/// runs daadwerkelijk veranderen — niet bij elke SwiftUI `body`-evaluatie.
///
/// Zonder deze laag riep elke view die `GameEngine.calculate(from: healthKit.runs)` als computed
/// property had dat opnieuw aan bij elke redraw (elke `.animation()`-tick, elke tap op een
/// progress bar, etc.). Voor `weeklyTrend` betekent dat 8x `calculate` per redraw, en voor
/// `BadgesView` betekent het de dag-voor-dag streak-simulatie van `streakMilestone` opnieuw
/// uitvoeren voor élke badge, bij élke redraw — dat wordt zichtbaar traag zodra iemand een
/// jaar aan hardloopgeschiedenis heeft.
///
/// Singleton naar hetzelfde patroon als `HealthKitManager.shared`, en abonneert zich op diens
/// `runs`/`lifetimeRuns` via Combine.
@MainActor
final class GameStatsStore: ObservableObject {
    static let shared = GameStatsStore()

    /// De live spelscores (stamina/consistentie/snelheid/level), gebaseerd op het rollende venster.
    @Published private(set) var stats: GameStats = .empty
    /// Alle tussenliggende getallen achter `stats` — voor de detail-sheets en het debugscherm.
    @Published private(set) var breakdown: GameEngineDebugInfo = GameEngine.debugBreakdown(from: [])
    /// Substat-scores van de laatste 8 weken, voor de trendgrafieken in Stats.
    @Published private(set) var trend: [WeeklyTrendPoint] = []
    /// Wat vandaag heeft opgeleverd t.o.v. het begin van de dag, voor de Home-kaart.
    @Published private(set) var todaySummary = TodaySummary(
        hasRunToday: false, todaysRuns: [], totalDistanceKm: 0,
        staminaDelta: 0, consistencyDelta: 0, speedDelta: 0, xpGained: 0
    )
    /// Wat deze week heeft opgeleverd t.o.v. het begin van de week, voor de "Deze week"-kaart.
    @Published private(set) var weeklyRecap = WeeklyRecap(
        weekStart: Date(), hasRunThisWeek: false, weekRuns: [], totalDistanceKm: 0,
        levelAtWeekStart: 1, levelNow: 1, staminaDelta: 0, consistencyDelta: 0, speedDelta: 0, xpGained: 0,
        dayStatuses: []
    )
    /// Kale, beschrijvende loopstatistieken, gebaseerd op de volledige historie.
    @Published private(set) var runStats = RunStatsSummary.calculate(from: [])
    /// Persoonlijke records (langste run, snelste 5K/10K/halve marathon/marathon, beste week,
    /// etc.), ook gebaseerd op de volledige historie — zie PersonalRecords.
    @Published private(set) var personalRecords = PersonalRecords.calculate(from: [])
    /// Alle badges met hun huidige (on)behaald-status, gebaseerd op de volledige historie
    /// (m.u.v. de effort-badges, zie `BadgeEvaluationContext`).
    @Published private(set) var badgeStatuses: [BadgeStatus] = []

    /// Het ingestelde wedstrijddoel, of nil als er geen is. In tegenstelling tot de rest van
    /// deze store is dit geen afgeleide waarde maar een instelling — vandaar publiekelijk
    /// instelbaar (geen `private(set)`), en opgeslagen in UserDefaults zodat het een
    /// app-herstart overleeft. Wijzigen triggert automatisch een herberekening van
    /// raceReadiness via de Combine-subscriptie hieronder.
    @Published var raceGoal: RaceGoal? {
        didSet { saveRaceGoal() }
    }
    /// nil zolang er geen raceGoal is ingesteld.
    @Published private(set) var raceReadiness: RaceReadiness?

    /// Voorspelling wanneer het volgende level bereikt wordt, op basis van recent XP-tempo.
    @Published private(set) var levelForecast = LevelForecast(weeklyXPRate: 0, xpRemaining: 0, estimatedWeeks: nil)
    /// Welke substat (indien van toepassing) de laatste weken nauwelijks bewogen heeft.
    @Published private(set) var plateauDetection: PlateauDetection?

    private static let raceGoalStorageKey = "raceGoalData"

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Bewust hier opgevraagd i.p.v. als default-parameterwaarde (`= .shared`): een
        // default-argumentexpressie wordt niet als main-actor-isolated context geëvalueerd,
        // dus een main-actor-isolated static property als HealthKitManager.shared daar direct
        // gebruiken botst met de actor-isolatie. In de init-body (die wél main-actor-isolated
        // draait, want GameStatsStore is @MainActor) is dit gewoon een normale, veilige read.
        let healthKit = HealthKitManager.shared
        self.raceGoal = Self.loadRaceGoal()

        // CombineLatest stuurt bij subscriptie meteen de huidige waarde van beide publishers
        // door, dus dit zet ook de eerste berekening in gang zonder dat we die apart hoeven
        // te triggeren — en herberekent daarna telkens wanneer runs óf lifetimeRuns wijzigt.
        // Bewust GEEN raceGoal in deze subscriptie: dit is de dure pipeline (badges met de
        // dag-voor-dag streak-simulatie, weeklyTrend met 8x calculate, personal records) en
        // niets daarvan hangt af van het wedstrijddoel.
        Publishers.CombineLatest(healthKit.$runs, healthKit.$lifetimeRuns)
            .sink { [weak self] runs, lifetimeRuns in
                self?.recalculate(runs: runs, lifetimeRuns: lifetimeRuns)
            }
            .store(in: &cancellables)

        // Racegereedheid staat bewust in een eigen, veel goedkopere subscriptie (één
        // effectiveWeeklyVolume-berekening + één calculate-aanroep, geen badges/trend/records).
        // Zonder deze scheiding triggerde elke aanraking van de wedstrijddoel-editor in Profiel
        // — elke tik aan het datumwiel, elke stap op de afstand-stepper — de hele dure pipeline
        // hierboven opnieuw, wat voelbaar hapert bij een DatePicker die tijdens het scrollen
        // meerdere keren per seconde een wijziging afvuurt.
        Publishers.CombineLatest(healthKit.$runs, $raceGoal)
            .sink { [weak self] runs, raceGoal in
                self?.recalculateRaceReadiness(runs: runs, raceGoal: raceGoal)
            }
            .store(in: &cancellables)
    }

    /// Eén centrale plek die alle afgeleide state herberekent. `now`/`calendar` worden bewust
    /// hier vastgepind i.p.v. los in elke sub-berekening, zodat stats/breakdown/trend/
    /// todaySummary gegarandeerd op hetzelfde peilmoment gebaseerd zijn.
    ///
    /// Bewust `Task.detached`: dit rekenwerk (8x calculate voor de trend, 40 badges met o.a.
    /// de dag-voor-dag streak-simulatie) kan bij een lange loopgeschiedenis oplopen tot een
    /// merkbare hapering. Vanuit een @MainActor-context zou een gewone `Task { }` alsnog op de
    /// main actor blijven draaien (die erft de isolatie van de aanroeper) — `.detached` is nodig
    /// om dit daadwerkelijk van de main thread af te halen. Alle GameEngine/BadgeDefinition-
    /// functies zijn pure functies zonder gedeelde mutable state, dus veilig om hier aan te roepen.
    /// Pas de toewijzing aan de @Published properties (op MainActor.run) is UI-gebonden.
    private func recalculate(runs: [RunWorkout], lifetimeRuns: [RunWorkout]) {
        Task.detached(priority: .userInitiated) {
            let now = Date()
            let calendar = Calendar.current

            let stats = GameEngine.calculate(from: runs, now: now, calendar: calendar)
            let breakdown = GameEngine.debugBreakdown(from: runs, now: now, calendar: calendar)
            let trend = GameEngine.weeklyTrend(from: runs, now: now, calendar: calendar)
            let levelForecast = GameEngine.levelForecast(from: runs, now: now, calendar: calendar)
            let plateauDetection = GameEngine.detectPlateau(in: trend)
            let todaySummary = GameEngine.todaySummary(from: runs, now: now, calendar: calendar)
            let weeklyRecap = GameEngine.weeklyRecap(from: runs, now: now, calendar: calendar)
            let runStats = RunStatsSummary.calculate(from: lifetimeRuns, now: now, calendar: calendar)
            let personalRecords = PersonalRecords.calculate(from: lifetimeRuns, calendar: calendar)

            let context = BadgeEvaluationContext(lifetimeRuns: lifetimeRuns, recentClassifiedRuns: runs)
            let badgeStatuses = BadgeDefinition.all.map { definition in
                BadgeStatus(definition: definition, unlockedDate: definition.evaluate(context))
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.stats = stats
                self.breakdown = breakdown
                self.trend = trend
                self.levelForecast = levelForecast
                self.plateauDetection = plateauDetection
                self.todaySummary = todaySummary
                self.weeklyRecap = weeklyRecap
                self.runStats = runStats
                self.personalRecords = personalRecords
                self.badgeStatuses = badgeStatuses
            }
        }
    }

    /// Losse, goedkope herberekening voor racegereedheid — zie de subscriptie hierboven voor
    /// waarom dit niet in recalculate() zit.
    private func recalculateRaceReadiness(runs: [RunWorkout], raceGoal: RaceGoal?) {
        guard let raceGoal else {
            raceReadiness = nil
            return
        }
        raceReadiness = GameEngine.raceReadiness(goal: raceGoal, runs: runs, now: Date(), calendar: Calendar.current)
    }

    private func saveRaceGoal() {
        if let raceGoal, let data = try? JSONEncoder().encode(raceGoal) {
            UserDefaults.standard.set(data, forKey: Self.raceGoalStorageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.raceGoalStorageKey)
        }
    }

    private static func loadRaceGoal() -> RaceGoal? {
        guard let data = UserDefaults.standard.data(forKey: raceGoalStorageKey) else { return nil }
        return try? JSONDecoder().decode(RaceGoal.self, from: data)
    }
}
