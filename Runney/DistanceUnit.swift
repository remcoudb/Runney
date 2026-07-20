import Foundation

/// Centrale @AppStorage-sleutel zodat elk scherm dezelfde bron van waarheid gebruikt.
let distanceUnitStorageKey = "distanceUnit"

/// De maateenheid waarin afstanden aan de gebruiker getoond worden. Alle interne opslag en
/// GameEngine-berekeningen blijven altijd in kilometers (score-curves, badge-drempels,
/// PR-afstandsbanden, racegereedheid-doelen zijn allemaal in km) — dit type is puur een
/// presentatielaag die omrekent en formatteert, en raakt nooit de score-logica zelf aan.
/// `nonisolated`: format()/formatPace() worden overal aangeroepen vanuit nonisolated
/// contexten (PersonalRecord.valueText, StatDetailContent, etc.) binnen GameStatsStore's
/// Task.detached — zonder dit zouden die aanroepen niet compileren.
nonisolated enum DistanceUnit: String, CaseIterable, Identifiable {
    case kilometers
    case miles

    var id: String { rawValue }

    private var unitLength: UnitLength {
        switch self {
        case .kilometers: return .kilometers
        case .miles: return .miles
        }
    }

    /// Omrekeningsfactor km → mile, voor tempo-berekeningen waar Measurement net iets te
    /// omslachtig voor is (zie formatPace hieronder).
    private static let kmToMileFactor = 1.609344

    var abbreviation: String {
        switch self {
        case .kilometers: return String(localized: "km", comment: "Abbreviation for kilometers, shown after a distance value")
        case .miles: return String(localized: "mi", comment: "Abbreviation for miles, shown after a distance value")
        }
    }

    var displayName: String {
        switch self {
        case .kilometers: return String(localized: "Kilometers", comment: "Distance unit option in settings")
        case .miles: return String(localized: "Miles", comment: "Distance unit option in settings")
        }
    }

    /// Rekent een waarde die intern altijd in kilometers staat om naar deze eenheid.
    func convert(fromKm km: Double) -> Double {
        Measurement(value: km, unit: UnitLength.kilometers).converted(to: unitLength).value
    }

    /// Rekent een door de gebruiker ingevoerde waarde in déze eenheid terug naar kilometers,
    /// voor opslag/berekening (GameEngine/GoalType/RaceReadiness werken altijd intern in km).
    func convertToKm(_ value: Double) -> Double {
        Measurement(value: value, unit: unitLength).converted(to: .kilometers).value
    }

    /// Geformatteerde afstand, bv. "5.02 km" of "3.12 mi".
    func format(km: Double, decimals: Int = 2) -> String {
        String(format: "%.\(decimals)f %@", convert(fromKm: km), abbreviation)
    }

    /// Tempo (intern altijd sec/km) omgerekend en geformatteerd voor deze eenheid,
    /// bv. "5:12 /km" of "8:22 /mi".
    func formatPace(secPerKm: Double) -> String {
        guard secPerKm > 0 else { return "–" }
        let secPerUnit: Double
        switch self {
        case .kilometers: secPerUnit = secPerKm
        case .miles: secPerUnit = secPerKm * Self.kmToMileFactor
        }
        let minutes = Int(secPerUnit) / 60
        let seconds = Int(secPerUnit) % 60
        return String(format: "%d:%02d /%@", minutes, seconds, abbreviation)
    }
}
