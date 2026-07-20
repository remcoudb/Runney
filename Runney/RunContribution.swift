import Foundation

/// Wat één specifieke run heeft opgeleverd — bereikt door `GameEngine.calculate` twee keer
/// aan te roepen (net vóór en net ná deze ene run) en het verschil te nemen. Zelfde truc als
/// TodaySummary/WeeklyRecap al gebruiken voor een hele dag/week, hier toegepast op een
/// individuele run, zodat meerdere runs op één dag elk hun eigen, aparte terugblik krijgen
/// in plaats van alles samen te voegen.
nonisolated struct RunContribution {
    let staminaDelta: Int
    let consistencyDelta: Int
    let speedDelta: Int
    let xpGained: Int
    /// Stand van de stats vóór deze run — nodig om bv. "Stamina ging van 44 naar 48" te tonen,
    /// niet alleen het kale verschil.
    let staminaBefore: Int
    let consistencyBefore: Int
    let speedBefore: Int
}

nonisolated extension GameEngine {
    /// `allRuns` moet de volledige, opgehaalde runs-lijst zijn (niet alleen deze ene run) —
    /// de score-berekening kijkt immers naar recente geschiedenis (weekvolume, streak, etc.),
    /// dus die context is nodig om zowel de "voor" als "na"-stand correct te bepalen.
    static func runContribution(for run: RunWorkout, allRuns: [RunWorkout], calendar: Calendar = .current) -> RunContribution {
        let before = calculate(from: allRuns, now: run.startDate, calendar: calendar)
        let after = calculate(from: allRuns, now: run.endDate, calendar: calendar)
        return RunContribution(
            staminaDelta: after.stamina - before.stamina,
            consistencyDelta: after.consistency - before.consistency,
            speedDelta: after.speed - before.speed,
            xpGained: after.totalXP - before.totalXP,
            staminaBefore: before.stamina,
            consistencyBefore: before.consistency,
            speedBefore: before.speed
        )
    }
}
