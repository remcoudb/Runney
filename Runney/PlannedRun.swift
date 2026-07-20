import Foundation
import SwiftUI

/// Hoe zwaar een geplande run aanvoelt — puur een eigen inschatting van de gebruiker (net
/// als de rest van PlannedRun komt dit nergens automatisch uit voort), gebruikt voor de
/// stipjes-indicator in de weekweergave.
enum RunIntensity: String, Codable, CaseIterable, Identifiable {
    case easy, medium, hard

    var id: String { rawValue }

    /// 1 voor easy, 2 voor medium, 3 voor hard — rechtstreeks het aantal gevulde stipjes.
    var dotCount: Int {
        switch self {
        case .easy: return 1
        case .medium: return 2
        case .hard: return 3
        }
    }

    var color: Color {
        switch self {
        case .easy: return CozyPalette.stamina
        case .medium: return CozyPalette.speed
        case .hard: return RunIntensity.hardColor
        }
    }

    /// Geen bestaande CozyPalette-kleur is een echt rood (de vier categoriekleuren zijn
    /// groen/blauw/oranje/geel) — een zachte, gedempte rode tint past bij de rest van de
    /// pastel-achtige stijl, in plaats van een fel waarschuwingsrood.
    private static let hardColor = Color(red: 0.82, green: 0.32, blue: 0.30)

    var title: String {
        switch self {
        case .easy: return String(localized: "Easy", comment: "Run intensity")
        case .medium: return String(localized: "Medium", comment: "Run intensity")
        case .hard: return String(localized: "Hard", comment: "Run intensity")
        }
    }
}

/// Een door de gebruiker zelf ingepland trainingsmoment — komt nooit uit een algoritme in
/// deze app; de gebruiker voert 'm handmatig in vanuit een schema dat hij/zij elders al
/// heeft opgesteld. Puur "wat is het plan", los van wat er uiteindelijk gelopen is (zie
/// PlannedRunComparison voor die koppeling met de HealthKit-historie).
struct PlannedRun: Identifiable, Codable, Equatable {
    let id: UUID
    /// Alleen de kalenderdag is relevant, geen tijdstip — trainingsschema's plannen per dag,
    /// niet op de minuut.
    var date: Date
    /// Altijd in km opgeslagen, ongeacht de weergave-eenheid — zelfde conventie als overal
    /// elders in de app (GoalType, RaceGoal, etc.).
    var distanceKm: Double
    /// Doeltempo in sec/km. Bij een losse waarde (geen range) geldt dit als het target,
    /// met een vaste tolerantie voor "hoe dichtbij" (zie PlannedRunComparison).
    var targetPaceSecPerKm: Double
    /// Bovengrens (traagste toegestane tempo) in sec/km, voor schema's die een range opgeven
    /// (bijv. "tussen 5:20 en 5:40/km"). Nil = geen range, alleen het losse doeltempo hierboven.
    var targetPaceMaxSecPerKm: Double?
    /// Vrije tekst i.p.v. een vaste, beperkte lijst — zodat de gebruiker zijn eigen
    /// schema-terminologie kan gebruiken ("Tempoloop", "Lange duurloop", "Herstelloop", ...).
    var label: String
    var notes: String?
    var intensity: RunIntensity

    init(
        id: UUID = UUID(),
        date: Date,
        distanceKm: Double,
        targetPaceSecPerKm: Double,
        targetPaceMaxSecPerKm: Double? = nil,
        label: String,
        notes: String? = nil,
        intensity: RunIntensity = .medium
    ) {
        self.id = id
        self.date = date
        self.distanceKm = distanceKm
        self.targetPaceSecPerKm = targetPaceSecPerKm
        self.targetPaceMaxSecPerKm = targetPaceMaxSecPerKm
        self.label = label
        self.notes = notes
        self.intensity = intensity
    }

    /// Handmatig geschreven i.p.v. de automatisch gesynthetiseerde variant, puur om
    /// `intensity` een terugvalwaarde te geven — plannen die zijn opgeslagen vóórdat dit
    /// veld bestond, hebben deze sleutel niet in hun JSON staan, en zouden anders niet
    /// meer te decoderen zijn.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        distanceKm = try container.decode(Double.self, forKey: .distanceKm)
        targetPaceSecPerKm = try container.decode(Double.self, forKey: .targetPaceSecPerKm)
        targetPaceMaxSecPerKm = try container.decodeIfPresent(Double.self, forKey: .targetPaceMaxSecPerKm)
        label = try container.decode(String.self, forKey: .label)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        intensity = try container.decodeIfPresent(RunIntensity.self, forKey: .intensity) ?? .medium
    }

    var hasPaceRange: Bool { targetPaceMaxSecPerKm != nil }
}

/// Hoe een geplande run zich verhoudt tot wat er die kalenderdag daadwerkelijk gelopen is.
struct PlannedRunComparison {
    let plannedRun: PlannedRun
    /// nil als er die dag geen (matchende) run gevonden is.
    let matchedRun: RunWorkout?

    enum Status {
        /// Datum is vandaag of ligt in de toekomst, en er is nog niets gelopen.
        case upcoming
        /// Datum ligt in het verleden en er is geen run gevonden die dag.
        case missed
        /// Er is gelopen, en zowel afstand als tempo lagen binnen de marge.
        case onTarget
        /// Er is gelopen, maar afstand en/of tempo weken meer dan de marge af.
        case offTarget
    }

    /// Tolerantie voor afstand: 10% afwijking geldt nog als "op schema" — genoeg marge voor
    /// een iets afwijkende GPS-meting of een bewust net iets korter/langer rondje.
    private static let distanceTolerance = 0.10
    /// Vaste tolerantie (sec/km) rondom een los doeltempo zonder range. Ook toegepast als
    /// extra marge aan weerszijden van een expliciete range, om een net-buiten-de-lijn
    /// tempo niet meteen als "off target" te bestempelen.
    private static let paceToleranceSecPerKm = 15.0

    var isDistanceOnTarget: Bool {
        guard let matchedRun else { return false }
        let diff = abs(matchedRun.distanceKm - plannedRun.distanceKm)
        return diff <= plannedRun.distanceKm * Self.distanceTolerance
    }

    var isPaceOnTarget: Bool {
        guard let matchedRun else { return false }
        let pace = matchedRun.averagePaceSecPerKm
        if let max = plannedRun.targetPaceMaxSecPerKm {
            return pace >= plannedRun.targetPaceSecPerKm - Self.paceToleranceSecPerKm
                && pace <= max + Self.paceToleranceSecPerKm
        }
        return abs(pace - plannedRun.targetPaceSecPerKm) <= Self.paceToleranceSecPerKm
    }

    var status: Status {
        guard matchedRun != nil else {
            let startOfToday = Calendar.current.startOfDay(for: Date())
            return plannedRun.date >= startOfToday ? .upcoming : .missed
        }
        return (isDistanceOnTarget && isPaceOnTarget) ? .onTarget : .offTarget
    }

    /// Positief = verder dan gepland, negatief = korter dan gepland.
    var distanceDeltaKm: Double? {
        guard let matchedRun else { return nil }
        return matchedRun.distanceKm - plannedRun.distanceKm
    }

    /// Positief = trager dan gepland, negatief = sneller dan gepland. Vergelijkt met de
    /// dichtstbijzijnde rand van de range (of het losse doeltempo als er geen range is).
    var paceDeltaSecPerKm: Double? {
        guard let matchedRun else { return nil }
        let pace = matchedRun.averagePaceSecPerKm
        if let max = plannedRun.targetPaceMaxSecPerKm {
            if pace < plannedRun.targetPaceSecPerKm { return pace - plannedRun.targetPaceSecPerKm }
            if pace > max { return pace - max }
            return 0
        }
        return pace - plannedRun.targetPaceSecPerKm
    }
}

extension PlannedRun {
    /// Zoekt de best passende run van dezelfde kalenderdag. Bij meerdere runs die dag wordt
    /// de run gekozen die qua afstand het dichtst bij het doel ligt — vermoedelijk de
    /// bedoelde trainingsrun, in plaats van bijvoorbeeld een kort ommetje ernaast.
    func comparison(against runs: [RunWorkout], calendar: Calendar = .current) -> PlannedRunComparison {
        let sameDay = runs.filter { calendar.isDate($0.startDate, inSameDayAs: date) }
        let bestMatch = sameDay.min { abs($0.distanceKm - distanceKm) < abs($1.distanceKm - distanceKm) }
        return PlannedRunComparison(plannedRun: self, matchedRun: bestMatch)
    }
}
