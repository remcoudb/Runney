import Foundation

/// Het volledige, berekende overzicht van de speler op een gegeven moment.
/// Dit is puur een resultaat-struct — de berekening zelf gebeurt in GameEngine.
/// `nonisolated`: puur data, geconstrueerd vanuit GameEngine's nonisolated functies binnen
/// GameStatsStore's Task.detached — zonder dit zou die constructie niet compileren.
nonisolated struct GameStats: Equatable, Identifiable {
    /// Puur voor gebruik als sheet/fullScreenCover-item — geen inhoudelijke betekenis.
    var id: Int { totalXP }

    /// 0...100
    let stamina: Int
    /// 0...100
    let consistency: Int
    /// 0...100
    let speed: Int

    let level: Int
    /// Naam behorend bij het huidige level, bv. "Couch Potato" of "Halve Marathon Kampioen".
    let levelTitle: String
    let totalXP: Int
    /// XP die je al hebt binnen het huidige level.
    let xpIntoCurrentLevel: Int
    /// XP die nodig is om van huidig level naar het volgende te gaan. 0 als het hoogste level al bereikt is.
    let xpNeededForNextLevel: Int

    /// 0...1, handig om direct in een ProgressView te stoppen. Volle balk als het maximale level bereikt is.
    var levelProgress: Double {
        guard xpNeededForNextLevel > 0 else { return 1 }
        return Double(xpIntoCurrentLevel) / Double(xpNeededForNextLevel)
    }

    static let empty = GameStats(
        stamina: 0, consistency: 0, speed: 0,
        level: 1, levelTitle: "Couch Potato", totalXP: 0, xpIntoCurrentLevel: 0, xpNeededForNextLevel: 1000
    )
}
