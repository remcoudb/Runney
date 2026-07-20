import Foundation

/// Alle tussenliggende getallen achter een GameStats-berekening, puur voor testen/debuggen.
/// Niet bedoeld als onderdeel van de uiteindelijke productie-UI.
/// `nonisolated`: zelfde reden als GameStats — puur data, geconstrueerd binnen GameStatsStore's
/// Task.detached.
nonisolated struct GameEngineDebugInfo {
    struct WeekVolume: Identifiable {
        var id: Int { weeksAgo }
        let weeksAgo: Int
        let km: Double
        let runCount: Int
    }

    let stats: GameStats

    // Stamina
    let recentWeeks: [WeekVolume]
    let effectiveStaminaVolumeKm: Double

    // Consistentie
    let runsThisWeek: Int
    let streakWeeks: Int

    // Snelheid
    let fastestQualifyingPaceSecPerKm: Double?
    let hasTempoRunLast7Days: Bool
    let hasIntervalRunLast7Days: Bool

    // Algemeen
    let totalRunsFetched: Int
    /// Wanneer de app voor het eerst gestart is — startpunt voor XP-telling.
    let appInstallDate: Date
    /// Hoeveel van de opgehaalde runs meetellen voor XP (dus na appInstallDate).
    let xpEligibleRunCount: Int
}
