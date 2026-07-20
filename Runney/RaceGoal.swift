import Foundation

/// Een eenmalig, datum-gebonden wedstrijddoel — bewust los van het terugkerende "Persoonlijk
/// doel" (GoalType/UserGoal), dat over het wekelijkse/maandelijkse ritme gaat. Dit gaat over
/// één specifieke race op één specifieke datum.
/// `nonisolated`: `distanceKm` wordt gelezen binnen GameEngine.raceReadiness, dat nonisolated
/// is en binnen GameStatsStore's Task.detached draait.
nonisolated struct RaceGoal: Codable, Equatable {
    enum Distance: String, CaseIterable, Identifiable, Codable, Hashable {
        case fiveK, tenK, half, marathon, custom

        var id: String { rawValue }

        /// nil voor .custom — daar bepaalt RaceGoal.customKm de afstand.
        var km: Double? {
            switch self {
            case .fiveK: return 5
            case .tenK: return 10
            case .half: return 21.1
            case .marathon: return 42.2
            case .custom: return nil
            }
        }

        var title: String {
            switch self {
            case .fiveK: return "5K"
            case .tenK: return "10K"
            case .half: return String(localized: "Half Marathon", comment: "Race distance option")
            case .marathon: return String(localized: "Marathon", comment: "Race distance option")
            case .custom: return String(localized: "Custom distance", comment: "Race distance option")
            }
        }
    }

    var distanceType: Distance
    /// Alleen relevant als distanceType == .custom — bij een vaste afstand leidt distanceKm
    /// gewoon van distanceType.km, ongeacht wat hier staat.
    var customKm: Double
    var raceDate: Date

    var distanceKm: Double {
        distanceType.km ?? customKm
    }

    var title: String {
        distanceType.title
    }
}
