import Foundation

/// Pure, testbare rekenlaag. Geen HealthKit, geen UI — alleen [RunWorkout] in, GameStats uit.
/// `nonisolated`: net als GameConstants heeft dit type geen enkele gedeelde/main-actor-
/// gebonden state, en wordt sinds GameStatsStore's Task.detached-verplaatsing (zie daar)
/// vanuit een niet-main-actor-context aangeroepen — zonder dit zou dat niet compileren.
nonisolated enum GameEngine {

    static func calculate(from runs: [RunWorkout], now: Date = Date(), calendar: Calendar = .current) -> GameStats {
        let stamina = calculateStamina(runs: runs, now: now, calendar: calendar)
        let consistency = calculateConsistency(runs: runs, now: now, calendar: calendar)
        let speed = calculateSpeed(runs: runs, now: now, calendar: calendar)
        let (level, totalXP, xpIntoLevel, xpNeeded, levelTitle) = calculateLevel(runs: runs, now: now)

        return GameStats(
            stamina: stamina,
            consistency: consistency,
            speed: speed,
            level: level,
            levelTitle: levelTitle,
            totalXP: totalXP,
            xpIntoCurrentLevel: xpIntoLevel,
            xpNeededForNextLevel: xpNeeded
        )
    }

    /// Zelfde berekening als `calculate`, maar geeft ook alle tussenstappen terug — handig
    /// om tijdens het testen te zien *waarom* een score is wat hij is.
    static func debugBreakdown(from runs: [RunWorkout], now: Date = Date(), calendar: Calendar = .current) -> GameEngineDebugInfo {
        let stats = calculate(from: runs, now: now, calendar: calendar)

        let recentWeeks: [GameEngineDebugInfo.WeekVolume] = (0..<GameConstants.staminaSmoothingWeeks).map { weeksAgo in
            GameEngineDebugInfo.WeekVolume(
                weeksAgo: weeksAgo,
                km: weekVolumeKm(runs: runs, weeksAgo: weeksAgo, now: now, calendar: calendar),
                runCount: runCount(runs: runs, weeksAgo: weeksAgo, now: now, calendar: calendar)
            )
        }

        let lookback = calendar.date(byAdding: .day, value: -GameConstants.speedPaceLookbackDays, to: now)
        let qualifyingRuns = runs.filter {
            $0.startDate >= (lookback ?? .distantPast) && $0.startDate < now && $0.distanceKm >= GameConstants.speedMinDistanceForPaceRatingKm
        }
        let fastest = qualifyingRuns.min(by: { $0.averagePaceSecPerKm < $1.averagePaceSecPerKm })

        let bonusWindowStart = calendar.date(byAdding: .day, value: -GameConstants.speedBonusWindowDays, to: now) ?? .distantPast
        let recentRuns = runs.filter { $0.startDate >= bonusWindowStart && $0.startDate < now }

        return GameEngineDebugInfo(
            stats: stats,
            recentWeeks: recentWeeks,
            effectiveStaminaVolumeKm: effectiveWeeklyVolume(runs: runs, now: now, calendar: calendar),
            runsThisWeek: runCount(runs: runs, weeksAgo: 0, now: now, calendar: calendar),
            streakWeeks: consecutiveStreakWeeks(runs: runs, now: now, calendar: calendar),
            fastestQualifyingPaceSecPerKm: fastest?.averagePaceSecPerKm,
            hasTempoRunLast7Days: recentRuns.contains { $0.effortType.isTempo },
            hasIntervalRunLast7Days: recentRuns.contains { $0.effortType.isInterval },
            totalRunsFetched: runs.count,
            appInstallDate: AppInstallDate.value,
            xpEligibleRunCount: runs.filter { $0.startDate >= AppInstallDate.value && $0.startDate < now }.count
        )
    }

    // MARK: - Stamina

    private static func calculateStamina(runs: [RunWorkout], now: Date, calendar: Calendar) -> Int {
        let effectiveKm = effectiveWeeklyVolume(runs: runs, now: now, calendar: calendar)
        let score = interpolate(effectiveKm, curve: GameConstants.staminaScoreCurve)
        return clampToPercent(score)
    }

    /// Gewogen gemiddelde weekvolume over de laatste N weken — recentere weken wegen zwaarder.
    /// Dit is de "smoothing" die ervoor zorgt dat één rustweek de stamina niet meteen laat kelderen.
    /// `weeks`/`decay` zijn parameters (i.p.v. altijd Stamina's eigen constanten) zodat
    /// RaceReadiness.swift hetzelfde mechanisme kan hergebruiken met een eigen venster/afbouw —
    /// de defaults houden Stamina's bestaande gedrag exact ongewijzigd voor de call sites die
    /// geen expliciete waarden meegeven.
    static func effectiveWeeklyVolume(
        runs: [RunWorkout], now: Date, calendar: Calendar,
        weeks: Int = GameConstants.staminaSmoothingWeeks,
        decay: Double = GameConstants.staminaDecayFactor
    ) -> Double {
        var weightedSum = 0.0
        var weightTotal = 0.0

        for weekIndex in 0..<weeks {
            let volume = weekVolumeKm(runs: runs, weeksAgo: weekIndex, now: now, calendar: calendar)
            let weight = pow(decay, Double(weekIndex))
            weightedSum += volume * weight
            weightTotal += weight
        }

        guard weightTotal > 0 else { return 0 }
        return weightedSum / weightTotal
    }

    private static func weekVolumeKm(runs: [RunWorkout], weeksAgo: Int, now: Date, calendar: Calendar) -> Double {
        guard
            let weekEnd = calendar.date(byAdding: .day, value: -7 * weeksAgo, to: now),
            let weekStart = calendar.date(byAdding: .day, value: -7, to: weekEnd)
        else { return 0 }
        return runs
            .filter { $0.startDate >= weekStart && $0.startDate < weekEnd }
            .reduce(0) { $0 + $1.distanceKm }
    }

    // MARK: - Consistentie

    private static func calculateConsistency(runs: [RunWorkout], now: Date, calendar: Calendar) -> Int {
        let runsThisWeek = runCount(runs: runs, weeksAgo: 0, now: now, calendar: calendar)
        let weekCheckScore = scoreForRunCount(runsThisWeek, table: GameConstants.consistencyWeekCheckScores)

        let streakWeeks = consecutiveStreakWeeks(runs: runs, now: now, calendar: calendar)
        let streakScore = interpolate(Double(streakWeeks), curve: GameConstants.consistencyStreakScoreCurve)

        return clampToPercent(weekCheckScore + streakScore)
    }

    /// Aantal runs in de week die `weeksAgo` weken terug eindigt (0 = huidige rollende week).
    private static func runCount(runs: [RunWorkout], weeksAgo: Int, now: Date, calendar: Calendar) -> Int {
        guard
            let weekEnd = calendar.date(byAdding: .day, value: -7 * weeksAgo, to: now),
            let weekStart = calendar.date(byAdding: .day, value: -7, to: weekEnd)
        else { return 0 }
        return runs.filter { $0.startDate >= weekStart && $0.startDate < weekEnd }.count
    }

    /// Discrete stappen-lookup: hoogste drempel die nog gehaald wordt.
    private static func scoreForRunCount(_ count: Int, table: [(runs: Int, score: Double)]) -> Double {
        var result = 0.0
        for entry in table where count >= entry.runs {
            result = entry.score
        }
        return result
    }

    /// Telt hoeveel opeenvolgende weken (terugtellend vanaf nu) minimaal het streak-minimum halen.
    /// De huidige, nog lopende week (weeksAgo: 0) wordt bewust apart behandeld: die telt al mee
    /// zodra hij het minimum haalt, maar het *niet* (nog) halen ervan breekt de opgebouwde streak
    /// niet — de week is immers nog niet voorbij. Zonder deze uitzondering zou de streak elke
    /// week op zijn vroegst al op 0 staan totdat je die dag toevallig gelopen had, wat vooral op
    /// maandagochtend een flinke — en onterechte — knauw in de score geeft.
    private static func consecutiveStreakWeeks(runs: [RunWorkout], now: Date, calendar: Calendar) -> Int {
        let currentWeekCount = runCount(runs: runs, weeksAgo: 0, now: now, calendar: calendar)
        let currentWeekMet = currentWeekCount >= GameConstants.consistencyStreakMinRunsPerWeek

        var completedStreak = 0
        for weekIndex in 1..<GameConstants.consistencyMaxStreakSearchWeeks {
            let count = runCount(runs: runs, weeksAgo: weekIndex, now: now, calendar: calendar)
            if count >= GameConstants.consistencyStreakMinRunsPerWeek {
                completedStreak += 1
            } else {
                break
            }
        }

        return currentWeekMet ? completedStreak + 1 : completedStreak
    }

    // MARK: - Snelheid

    private static func calculateSpeed(runs: [RunWorkout], now: Date, calendar: Calendar) -> Int {
        let paceRating = paceRatingScore(runs: runs, now: now, calendar: calendar)
        let bonus = workoutTypeBonus(runs: runs, now: now, calendar: calendar)
        return clampToPercent(paceRating + bonus)
    }

    /// Max 60 punten: gebaseerd op de snelste ~5km-run van de laatste 30 dagen.
    private static func paceRatingScore(runs: [RunWorkout], now: Date, calendar: Calendar) -> Double {
        guard let lookback = calendar.date(byAdding: .day, value: -GameConstants.speedPaceLookbackDays, to: now) else {
            return 0
        }
        let candidates = runs.filter {
            $0.startDate >= lookback && $0.startDate < now && $0.distanceKm >= GameConstants.speedMinDistanceForPaceRatingKm
        }
        guard let fastest = candidates.min(by: { $0.averagePaceSecPerKm < $1.averagePaceSecPerKm }) else {
            return 0
        }
        return interpolate(fastest.averagePaceSecPerKm, curve: GameConstants.speedPaceRatingCurve)
    }

    /// Max 40 punten: +20 als er een tempoloop is geweest in de laatste 7 dagen, +20 voor een intervaltraining.
    /// De classificatie zelf (isTempo/isInterval) gebeurt in HealthKitManager bij het ophalen van de runs.
    private static func workoutTypeBonus(runs: [RunWorkout], now: Date, calendar: Calendar) -> Double {
        guard let windowStart = calendar.date(byAdding: .day, value: -GameConstants.speedBonusWindowDays, to: now) else {
            return 0
        }
        let recentRuns = runs.filter { $0.startDate >= windowStart && $0.startDate < now }

        var bonus = 0.0
        if recentRuns.contains(where: { $0.effortType.isTempo }) {
            bonus += GameConstants.speedBonusPointsPerType
        }
        if recentRuns.contains(where: { $0.effortType.isInterval }) {
            bonus += GameConstants.speedBonusPointsPerType
        }
        return bonus
    }

    // MARK: - Level & XP

    private static func calculateLevel(runs: [RunWorkout], now: Date) -> (level: Int, totalXP: Int, xpIntoLevel: Int, xpNeeded: Int, title: String) {
        // Alleen runs sinds het eerste gebruik van de app tellen mee voor XP — oude
        // HealthKit-historie mag stamina/consistentie/snelheid voeden, maar niet meteen
        // een hoog level opleveren voor iemand die de app net geïnstalleerd heeft.
        // De bovengrens (< now) zorgt dat "het level zoals het toen was" correct kan
        // worden herberekend door now terug te schuiven (zie GameEngine.todaySummary).
        let eligibleRuns = runs.filter { $0.startDate >= AppInstallDate.value && $0.startDate < now }

        let totalXP = eligibleRuns.reduce(0.0) { $0 + $1.distanceKm * GameConstants.xpPerKm }
        let totalXPInt = Int(totalXP.rounded())

        let thresholds = GameConstants.levelThresholds
        // Zoek het hoogste level waarvan de XP-drempel gehaald is.
        var currentIndex = 0
        for (index, entry) in thresholds.enumerated() {
            if totalXPInt >= entry.xpRequired {
                currentIndex = index
            } else {
                break
            }
        }

        let current = thresholds[currentIndex]
        let nextIndex = currentIndex + 1
        let xpIntoLevel = totalXPInt - current.xpRequired

        let xpNeeded: Int
        if nextIndex < thresholds.count {
            xpNeeded = thresholds[nextIndex].xpRequired - current.xpRequired
        } else {
            // Hoogste level al bereikt — geen volgende drempel (tot we meer levels toevoegen).
            xpNeeded = 0
        }

        // NSLocalizedString i.p.v. de nieuwere String(localized:) syntax, omdat dit een
        // dynamische runtime-string is (uit een array-element) i.p.v. een letterlijke
        // string in de code — dat werkt met beide APIs tegen dezelfde vertaalcatalogus,
        // maar NSLocalizedString is hiervoor de ondubbelzinnig correcte keuze.
        let localizedTitle = NSLocalizedString(current.titleEN, comment: "Level title")
        return (current.level, totalXPInt, xpIntoLevel, xpNeeded, localizedTitle)
    }

    // MARK: - Gedeelde helpers

    /// Generieke lineaire interpolatie tussen ankerpunten (x oplopend gesorteerd).
    /// Onder het eerste punt = eerste y, boven het laatste punt = laatste y (cap aan beide kanten).
    /// Werkt voor elke curve, ongeacht of y stijgt of daalt met x (bv. stamina-km vs. snelheids-tempo).
    private static func interpolate(_ x: Double, curve: [(Double, Double)]) -> Double {
        guard let first = curve.first, let last = curve.last else { return 0 }
        if x <= first.0 { return first.1 }
        if x >= last.0 { return last.1 }

        for i in 0..<(curve.count - 1) {
            let lower = curve[i]
            let upper = curve[i + 1]
            if x >= lower.0 && x <= upper.0 {
                let t = (x - lower.0) / (upper.0 - lower.0)
                return lower.1 + t * (upper.1 - lower.1)
            }
        }
        return last.1
    }

    private static func clampToPercent(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(value.rounded()).clamped(to: 0...100)
    }
}

/// `nonisolated`: gemist bij de eerdere ronde, want dit is een extensie op Int (een heel
/// ander type dan GameEngine) en erft dus niets van GameEngine's eigen nonisolated-status.
/// Wordt aangeroepen vanuit clampToPercent, binnen GameStatsStore's Task.detached.
private nonisolated extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
