import Foundation

/// Eén meetpunt in de trendgrafiek: de drie substat-scores zoals ze aan het eind van die week waren.
/// `nonisolated`: puur data, geconstrueerd binnen GameStatsStore's Task.detached.
nonisolated struct WeeklyTrendPoint: Identifiable {
    let id = UUID()
    let weeksAgo: Int
    let date: Date
    let stamina: Int
    let consistency: Int
    let speed: Int
}

/// `nonisolated`: een extensie erft NIET automatisch de nonisolated-status van het type
/// zelf als de extensie in een ander bestand staat dan de hoofddeclaratie — vandaar hier
/// expliciet herhaald (aangeroepen binnen GameStatsStore's Task.detached).
nonisolated extension GameEngine {
    /// Berekent de substat-scores voor elk van de laatste `weeks` weken, door `calculate`
    /// telkens met een teruggeschoven `now` aan te roepen. Geen aparte opslag van historische
    /// scores nodig — de berekening is puur, dus "de score van 3 weken geleden" is gewoon
    /// "bereken alsof het toen 3 weken geleden was", met dezelfde volledige runs-lijst.
    static func weeklyTrend(from runs: [RunWorkout], weeks: Int = 8, now: Date = Date(), calendar: Calendar = .current) -> [WeeklyTrendPoint] {
        (0..<weeks).reversed().compactMap { weeksAgo -> WeeklyTrendPoint? in
            guard let asOf = calendar.date(byAdding: .day, value: -7 * weeksAgo, to: now) else { return nil }
            let stats = calculate(from: runs, now: asOf, calendar: calendar)
            return WeeklyTrendPoint(
                weeksAgo: weeksAgo,
                date: asOf,
                stamina: stats.stamina,
                consistency: stats.consistency,
                speed: stats.speed
            )
        }
    }
}
