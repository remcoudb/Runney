import Foundation

/// Voorspelling van wanneer het volgende level bereikt wordt, op basis van je recente
/// XP-tempo — een concrete ETA i.p.v. alleen een voortgangsbalk.
/// `nonisolated`: puur data, geconstrueerd binnen GameStatsStore's Task.detached.
nonisolated struct LevelForecast {
    /// Hoeveel XP je gemiddeld per week verdient, gemeten over de laatste
    /// GameConstants.levelForecastLookbackWeeks weken.
    let weeklyXPRate: Double
    let xpRemaining: Int
    /// nil als er geen zinvolle voorspelling te maken is: geen recente XP-opbouw (tempo 0 of
    /// negatief kan niet voorkomen, maar wél 0 bij stilstand), of het hoogste level al bereikt.
    let estimatedWeeks: Int?
}

/// `nonisolated`: zie GameEngineTrend.swift voor waarom dit expliciet herhaald moet worden.
nonisolated extension GameEngine {
    /// Vergelijkt totalXP nu met totalXP een aantal weken terug (zelfde truc als
    /// todaySummary/weeklyRecap: `calculate` met een teruggeschoven `now` aanroepen) om een
    /// gemiddeld weektempo te bepalen, en rekent daarmee door naar een ETA voor het volgende level.
    static func levelForecast(
        from runs: [RunWorkout], now: Date = Date(), calendar: Calendar = .current,
        lookbackWeeks: Int = GameConstants.levelForecastLookbackWeeks
    ) -> LevelForecast {
        let statsNow = calculate(from: runs, now: now, calendar: calendar)

        guard statsNow.xpNeededForNextLevel > 0 else {
            // Hoogste level al bereikt — geen "volgende level" om naartoe te tellen.
            return LevelForecast(weeklyXPRate: 0, xpRemaining: 0, estimatedWeeks: nil)
        }

        let pastDate = calendar.date(byAdding: .weekOfYear, value: -lookbackWeeks, to: now) ?? now
        let statsPast = calculate(from: runs, now: pastDate, calendar: calendar)

        let xpGained = statsNow.totalXP - statsPast.totalXP
        let weeklyRate = Double(xpGained) / Double(lookbackWeeks)
        let xpRemaining = statsNow.xpNeededForNextLevel - statsNow.xpIntoCurrentLevel

        let estimatedWeeks: Int? = weeklyRate > 0
            ? Int((Double(xpRemaining) / weeklyRate).rounded(.up))
            : nil

        return LevelForecast(weeklyXPRate: weeklyRate, xpRemaining: xpRemaining, estimatedWeeks: estimatedWeeks)
    }
}
