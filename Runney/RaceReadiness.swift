import Foundation

/// Eén meetpunt in de racegereedheid-trendgrafiek — zelfde opzet als WeeklyTrendPoint in
/// GameEngineTrend.swift, maar dan voor de racegereedheid-score i.p.v. de drie substats.
/// `nonisolated`: puur data, geconstrueerd binnen GameStatsStore's Task.detached.
nonisolated struct RaceReadinessTrendPoint: Identifiable {
    let id = UUID()
    let weeksAgo: Int
    let date: Date
    let score: Int
}

/// Racegereedheid: hoe klaar ben je, gegeven je huidige training, voor een specifiek
/// wedstrijddoel? Drie factoren vormen samen een score van 0-100 — zie GameConstants voor
/// de gewichten/drempels, die bewust aanpasbaar zijn zonder deze rekenlaag te hoeven lezen.
/// `nonisolated`: puur data, geconstrueerd binnen GameEngine.raceReadiness (nonisolated),
/// binnen GameStatsStore's Task.detached.
nonisolated struct RaceReadiness {
    let goal: RaceGoal
    /// Kan negatief zijn als de wedstrijddatum al voorbij is — zie hasRacePassed.
    let weeksRemaining: Int
    let isInTaperWindow: Bool
    /// Of er minstens één run was binnen raceReadinessTaperActivityWindowDays vóór het
    /// échte "nu" (dus niet het bevroren meetmoment) — alleen relevant tijdens de taper, om
    /// "minder trainen" (prima) te onderscheiden van "helemaal niks doen" (niet de bedoeling).
    let hasRunRecently: Bool

    let longestRunKm: Double
    /// Hoeveel weken geleden de (na recency-weging) beste kwalificerende run was — getoond in
    /// het detailscherm zodat duidelijk is waarom de score lager kan zijn dan de kale
    /// km-verhouding zou suggereren.
    let longestRunWeeksAgo: Int
    /// Afgerond op hele kilometers (bv. 17 i.p.v. 17,302) — zowel voor een opgeruimde weergave
    /// als omdat de score dan ook echt op 100% staat zodra je die ronde 17 km haalt, in plaats
    /// van net onder de 100% te blijven steken door een decimaal die niemand ziet.
    let longestRunTargetKm: Double
    let longestRunScore: Int

    let weeklyVolumeKm: Double
    /// Zelfde afronding als longestRunTargetKm, en om dezelfde reden.
    let weeklyVolumeTargetKm: Double
    let weeklyVolumeScore: Int

    let consistencyScore: Int
    let consistencyContribution: Int

    var totalScore: Int {
        min(max(longestRunScore + weeklyVolumeScore + consistencyContribution, 0), 100)
    }

    var hasRacePassed: Bool { weeksRemaining < 0 }

    /// Korte, bemoedigende statustekst. Taper-advies krijgt altijd voorrang op de score zodra
    /// je in het laatste stuk voor de wedstrijd zit — een longrun proberen inhalen vlak van
    /// tevoren is juist riskant, dus de boodschap moet daar niet vanaf hangen hoe hoog de
    /// score toevallig is. Binnen de taper maakt het bericht zelf nog wel onderscheid tussen
    /// "minder trainen" (hasRunRecently) en "helemaal gestopt" (!hasRunRecently) — dat verschil
    /// raakt bewust alleen deze tekst, niet het (bevroren) cijfer zelf.
    var statusMessage: String {
        if hasRacePassed {
            return String(localized: "This race has already happened.", comment: "Race readiness status message")
        }
        if isInTaperWindow {
            return hasRunRecently
                ? String(localized: "Almost there! Focus on rest and tapering now, not another big run.", comment: "Race readiness status message")
                : String(localized: "Almost there! Keep moving lightly now and then to stay sharp — going completely still isn't the goal either.", comment: "Race readiness status message")
        }
        switch totalScore {
        case 80...100: return String(localized: "You're ready for it!", comment: "Race readiness status message")
        case 60..<80: return String(localized: "Well on track — keep up this pace.", comment: "Race readiness status message")
        case 40..<60: return String(localized: "Still work to do, but there's plenty of time.", comment: "Race readiness status message")
        default: return String(localized: "Time to seriously start building up.", comment: "Race readiness status message")
        }
    }
}

/// `nonisolated`: zie GameEngineTrend.swift voor waarom dit expliciet herhaald moet worden.
nonisolated extension GameEngine {
    /// Berekent racegereedheid voor een specifiek wedstrijddoel. Kijkt bewust naar een recent
    /// venster (GameConstants.raceReadinessLookbackWeeks) voor de langste run en het
    /// weekvolume, niet de volledige geschiedenis — dit gaat over je huidige opbouw, niet je
    /// lifetime record (dat zou een marathon van twee jaar geleden een halve marathon nu
    /// ten onrechte "klaar" laten lijken).
    static func raceReadiness(goal: RaceGoal, runs: [RunWorkout], now: Date = Date(), calendar: Calendar = .current) -> RaceReadiness {
        let weeksRemaining = calendar.dateComponents([.weekOfYear], from: now, to: goal.raceDate).weekOfYear ?? 0
        let isInTaperWindow = weeksRemaining >= 0 && weeksRemaining <= GameConstants.raceReadinessTaperWeeks

        // Zodra je in de taper zit, bevriezen we het meetmoment op het begin van de taper-
        // periode i.p.v. steeds het letterlijke "nu" te gebruiken. Bewust minder kilometers en
        // een kortere longrun maken is precies het juiste gedrag vlak voor een wedstrijd — zonder
        // deze bevriezing zou dat de score juist omlaag trekken, terwijl dat het tegenovergestelde
        // van "minder klaar" betekent. Racegereedheid gaat dan over wat je vóór de taper hebt
        // opgebouwd, niet over wat je tijdens de taper (bewust) laat liggen.
        let evaluationDate = isInTaperWindow
            ? (calendar.date(byAdding: .weekOfYear, value: -GameConstants.raceReadinessTaperWeeks, to: goal.raceDate) ?? now)
            : now

        let lookbackStart = calendar.date(byAdding: .weekOfYear, value: -GameConstants.raceReadinessLookbackWeeks, to: evaluationDate) ?? evaluationDate
        let recentRuns = runs.filter { $0.startDate >= lookbackStart && $0.startDate < evaluationDate }

        // Zoekt de run met de hoogste, recency-gewogen "effectieve" afstand — niet zomaar de
        // langste rauwe afstand. Zie recencyMultiplier hieronder voor de precieze curve.
        let bestQualifyingRun = recentRuns.max { lhs, rhs in
            effectiveLongRunDistance(for: lhs, asOf: evaluationDate) < effectiveLongRunDistance(for: rhs, asOf: evaluationDate)
        }
        let longestRunKm = bestQualifyingRun?.distanceKm ?? 0
        let longestRunEffectiveKm = bestQualifyingRun.map { effectiveLongRunDistance(for: $0, asOf: evaluationDate) } ?? 0
        let longestRunWeeksAgo = bestQualifyingRun.map {
            Int((evaluationDate.timeIntervalSince($0.startDate) / (7 * 24 * 3600)).rounded())
        } ?? 0

        let longestRunTargetKm = (goal.distanceKm * GameConstants.raceReadinessLongestRunFraction).rounded()
        let longestRunScore = longestRunTargetKm > 0
            ? min(longestRunEffectiveKm / longestRunTargetKm, 1.0) * GameConstants.raceReadinessLongestRunWeight
            : 0

        // Hergebruikt hetzelfde mechanisme als Stamina (gewogen gemiddelde, recentere weken
        // wegen zwaarder) — zie GameEngine.effectiveWeeklyVolume — maar bewust NIET de defaults
        // (Stamina's 4 weken / 0,6-afbouw): racegereedheid kijkt over hetzelfde 8-wekenvenster
        // als de longrun-factor hierboven, met een zachtere afbouw zodat ook week 6-7 nog
        // betekenisvol meetellen (zie GameConstants voor de precieze afweging).
        let weeklyVolumeKm = effectiveWeeklyVolume(
            runs: runs, now: evaluationDate, calendar: calendar,
            weeks: GameConstants.raceReadinessLookbackWeeks,
            decay: GameConstants.raceReadinessWeeklyVolumeDecayFactor
        )
        let weeklyVolumeTargetKm = (goal.distanceKm * GameConstants.raceReadinessWeeklyVolumeMultiplier).rounded()
        let weeklyVolumeScore = weeklyVolumeTargetKm > 0
            ? min(weeklyVolumeKm / weeklyVolumeTargetKm, 1.0) * GameConstants.raceReadinessWeeklyVolumeWeight
            : 0

        // Ook Consistentie bevriest mee: minder vaak lopen tijdens een taper is er ook daar
        // het juiste gedrag, niet een teken van minder klaar zijn.
        let stats = calculate(from: runs, now: evaluationDate, calendar: calendar)
        let consistencyContribution = Double(stats.consistency) / 100 * GameConstants.raceReadinessConsistencyWeight

        // Bewust het échte "nu", niet evaluationDate: dit checkt of er tijdens de taper zelf
        // nog licht getraind is, niet of er vóór de taper genoeg is opgebouwd (dat doen de
        // drie factoren hierboven al, bevroren).
        let activityWindowStart = calendar.date(
            byAdding: .day, value: -GameConstants.raceReadinessTaperActivityWindowDays, to: now
        ) ?? now
        let hasRunRecently = runs.contains { $0.startDate >= activityWindowStart && $0.startDate <= now }

        return RaceReadiness(
            goal: goal,
            weeksRemaining: weeksRemaining,
            isInTaperWindow: isInTaperWindow,
            hasRunRecently: hasRunRecently,
            longestRunKm: longestRunKm,
            longestRunWeeksAgo: longestRunWeeksAgo,
            longestRunTargetKm: longestRunTargetKm,
            longestRunScore: Int(longestRunScore.rounded()),
            weeklyVolumeKm: weeklyVolumeKm,
            weeklyVolumeTargetKm: weeklyVolumeTargetKm,
            weeklyVolumeScore: Int(weeklyVolumeScore.rounded()),
            consistencyScore: stats.consistency,
            consistencyContribution: Int(consistencyContribution.rounded())
        )
    }

    /// Racegereedheid-score voor elk van de laatste `weeks` weken — zelfde "terugschuiven"-
    /// truc als GameEngine.weeklyTrend: `raceReadiness` telkens met een teruggeschoven `now`
    /// aanroepen, geen aparte opslag van historische scores nodig. Alleen zinvol zolang het
    /// wedstrijddoel zelf al bestond in die periode (een score van vóórdat je het doel instelde
    /// zou niks betekenen) — vandaar de `goalCreatedNotBefore`-ondergrens.
    static func raceReadinessTrend(
        goal: RaceGoal, runs: [RunWorkout], weeks: Int = 8, now: Date = Date(), calendar: Calendar = .current
    ) -> [RaceReadinessTrendPoint] {
        (0..<weeks).reversed().compactMap { weeksAgo -> RaceReadinessTrendPoint? in
            guard let asOf = calendar.date(byAdding: .day, value: -7 * weeksAgo, to: now) else { return nil }
            let readiness = raceReadiness(goal: goal, runs: runs, now: asOf, calendar: calendar)
            return RaceReadinessTrendPoint(weeksAgo: weeksAgo, date: asOf, score: readiness.totalScore)
        }
    }

    /// Hoe zwaar een run van `weeksAgo` geleden nog meetelt (0...1). Blijft op 100% tot en met
    /// raceReadinessLongestRunPlateauWeeks, neemt daarna lineair af tot
    /// raceReadinessLongestRunMinRecencyMultiplier aan het einde van het lookback-venster.
    private static func recencyMultiplier(weeksAgo: Double) -> Double {
        let plateau = Double(GameConstants.raceReadinessLongestRunPlateauWeeks)
        guard weeksAgo > plateau else { return 1.0 }

        let decayRange = Double(GameConstants.raceReadinessLookbackWeeks) - plateau
        guard decayRange > 0 else { return 1.0 }

        let progress = min(max((weeksAgo - plateau) / decayRange, 0), 1)
        let floor = GameConstants.raceReadinessLongestRunMinRecencyMultiplier
        return 1.0 - progress * (1.0 - floor)
    }

    /// De rauwe afstand van een run, vermenigvuldigd met hoe recent die was t.o.v. `asOf`
    /// (het meetmoment — normaal "nu", maar bevroren op taper-start tijdens de taper) — dit is
    /// wat we vergelijken om de "beste" kwalificerende run te vinden, niet de kale afstand.
    private static func effectiveLongRunDistance(for run: RunWorkout, asOf: Date) -> Double {
        let weeksAgo = asOf.timeIntervalSince(run.startDate) / (7 * 24 * 3600)
        return run.distanceKm * recencyMultiplier(weeksAgo: weeksAgo)
    }
}
