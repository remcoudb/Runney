import Foundation

/// Alles wat de "Vandaag"-kaart op Home nodig heeft: de runs van vandaag, en wat elk
/// onderdeel daardoor veranderde t.o.v. de stand aan het begin van de dag.
/// `nonisolated`: puur data, geconstrueerd binnen GameStatsStore's Task.detached.
nonisolated struct TodaySummary {
    let hasRunToday: Bool
    let todaysRuns: [RunWorkout]
    let totalDistanceKm: Double

    let staminaDelta: Int
    let consistencyDelta: Int
    let speedDelta: Int
    let xpGained: Int
}

/// `nonisolated`: zie GameEngineTrend.swift voor waarom dit expliciet herhaald moet worden.
nonisolated extension GameEngine {
    /// Vergelijkt de score van nu met de score zoals die was bij het begin van vandaag (dus
    /// zonder de runs van vandaag) — het verschil is precies wat vandaag heeft opgeleverd.
    /// Dit hergebruikt `calculate` puur door `now` naar het begin van de dag terug te schuiven;
    /// werkt correct dankzij de bovengrens-filters (zie GameEngine.calculate).
    static func todaySummary(from runs: [RunWorkout], now: Date = Date(), calendar: Calendar = .current) -> TodaySummary {
        let startOfToday = calendar.startOfDay(for: now)
        let todaysRuns = runs
            .filter { $0.startDate >= startOfToday && $0.startDate < now }
            .sorted { $0.startDate < $1.startDate }

        let statsNow = calculate(from: runs, now: now, calendar: calendar)
        let statsBeforeToday = calculate(from: runs, now: startOfToday, calendar: calendar)

        return TodaySummary(
            hasRunToday: !todaysRuns.isEmpty,
            todaysRuns: todaysRuns,
            totalDistanceKm: todaysRuns.reduce(0) { $0 + $1.distanceKm },
            staminaDelta: statsNow.stamina - statsBeforeToday.stamina,
            consistencyDelta: statsNow.consistency - statsBeforeToday.consistency,
            speedDelta: statsNow.speed - statsBeforeToday.speed,
            xpGained: statsNow.totalXP - statsBeforeToday.totalXP
        )
    }
}
