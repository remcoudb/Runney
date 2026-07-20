import SwiftUI

/// Eén gedetecteerd plateau: welke substat, en wat te proberen om er weer beweging in te krijgen.
/// `nonisolated`: puur data, geconstrueerd binnen GameStatsStore's Task.detached.
nonisolated struct PlateauDetection {
    let statLabel: String
    let color: Color
    let suggestion: String
}

/// `nonisolated`: zie GameEngineTrend.swift voor waarom dit expliciet herhaald moet worden.
nonisolated extension GameEngine {
    /// Kijkt naar de laatste GameConstants.plateauDetectionWeeks weken uit de trend en meldt
    /// de eerste substat (in prioriteitsvolgorde Snelheid → Stamina → Consistentie) die binnen
    /// die weken nauwelijks bewogen heeft. Een substat die simpelweg nog nooit gestart is
    /// (bv. Snelheid op 0 omdat er nooit een tempoloop was) wordt genegeerd — dat is geen
    /// plateau, dat is "nog niet begonnen".
    static func detectPlateau(in trend: [WeeklyTrendPoint]) -> PlateauDetection? {
        let weeks = GameConstants.plateauDetectionWeeks
        guard trend.count >= weeks else { return nil }
        let recentWeeks = Array(trend.suffix(weeks))

        func isFlat(_ values: [Int]) -> Bool {
            guard let minValue = values.min(), let maxValue = values.max(), let latest = values.last else { return false }
            guard latest >= GameConstants.plateauDetectionMinValue else { return false }
            return (maxValue - minValue) <= GameConstants.plateauDetectionMaxVariance
        }

        if isFlat(recentWeeks.map(\.speed)) {
            return PlateauDetection(
                statLabel: String(localized: "Speed", comment: "Substat name"),
                color: CozyPalette.speed,
                suggestion: String(localized: "Try an interval training to give your pace a boost.", comment: "Plateau suggestion")
            )
        }
        if isFlat(recentWeeks.map(\.stamina)) {
            return PlateauDetection(
                statLabel: String(localized: "Stamina", comment: "Substat name"),
                color: CozyPalette.stamina,
                suggestion: String(localized: "Build up your weekly kilometers a bit further.", comment: "Plateau suggestion")
            )
        }
        if isFlat(recentWeeks.map(\.consistency)) {
            return PlateauDetection(
                statLabel: String(localized: "Consistency", comment: "Substat name"),
                color: CozyPalette.consistency,
                suggestion: String(localized: "Add an extra easy run this week.", comment: "Plateau suggestion")
            )
        }
        return nil
    }
}
