import Foundation

/// Bepaalt (en onthoudt, via UserDefaults) wanneer de app voor het eerst gestart is op dit toestel.
/// Gebruikt als startpunt voor XP/Level: runs van vóór dit moment tellen wel mee voor
/// stamina/consistentie/snelheid (die kijken naar recente HealthKit-historie), maar niet voor XP —
/// zo groeit XP alleen met runs die je maakt terwijl je de app daadwerkelijk gebruikt.
/// `nonisolated`: gebruikt binnen GameEngine.calculateLevel en BadgeDefinition.levelMilestone,
/// beide aangeroepen vanuit GameStatsStore's Task.detached. UserDefaults zelf is thread-safe,
/// dus de toegang hier vanaf een achtergrondthread is functioneel geen probleem.
nonisolated enum AppInstallDate {
    private static let key = "appInstallDate"

    /// Eén keer per app-launch bepaald (en de allereerste keer meteen weggeschreven).
    static let value: Date = {
        if let stored = UserDefaults.standard.object(forKey: key) as? Date {
            return stored
        }
        let now = Date()
        UserDefaults.standard.set(now, forKey: key)
        return now
    }()
}
