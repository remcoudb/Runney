import Foundation

/// `nonisolated`: zie GameEngineTrend.swift voor waarom dit expliciet herhaald moet worden.
nonisolated extension GameEngine {
    /// Het hoogste streak-mijlpaal dat een gegeven aantal opeenvolgende weken al gehaald heeft,
    /// of nil als er nog geen enkele gehaald is. Hergebruikt dezelfde ankerpunten als de
    /// consistentie-score (GameConstants.consistencyStreakScoreCurve) — geen aparte lijst met
    /// magic numbers die uit de pas kan gaan lopen met de score-curve.
    static func highestStreakMilestone(for streakWeeks: Int) -> Int? {
        let milestones = GameConstants.consistencyStreakScoreCurve
            .map { Int($0.weeks) }
            .filter { $0 > 0 }
            .sorted()
        return milestones.last(where: { streakWeeks >= $0 })
    }
}
