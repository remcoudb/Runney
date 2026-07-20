import Foundation

/// Classificatie van het type inspanning binnen een run, gebruikt voor de Snelheid workout-type bonus.
/// Beide kunnen in theorie tegelijk `true` zijn, al is dat in de praktijk zeldzaam.
/// `nonisolated`: puur een waardetype zonder eigen state — moet ook bruikbaar zijn vanuit de
/// nonisolated TaskGroup-taken in HealthKitManager (parallelle effort-classificatie).
nonisolated struct RunEffortType: Hashable {
    let isTempo: Bool
    let isInterval: Bool

    static let none = RunEffortType(isTempo: false, isInterval: false)
}
