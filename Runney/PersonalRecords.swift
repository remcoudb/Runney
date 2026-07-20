import Foundation

/// Wat voor soort record dit is — bepaalt hoe PersonalRecordsView de hoofd- en detailtekst
/// opbouwt. Bewust geen kant-en-klare, in km vastgebakken strings meer (zoals voorheen):
/// de eenheid (km/miles) is een live gebruikersinstelling, en dit model wordt gecachet in
/// GameStatsStore en dus niet herberekend zodra alleen de eenheid verandert — de weergave
/// moet dus zelf, op render-tijd, met de actuele DistanceUnit formatteren.
/// `nonisolated`: puur data, geconstrueerd binnen GameStatsStore's Task.detached.
nonisolated enum PersonalRecordKind {
    /// Hoofdwaarde = afstand van `run`.
    case distance
    /// Hoofdwaarde = tempo van `run`.
    case pace
    /// Hoofdwaarde = duur van `run` (tijd converteert niet met de eenheid), detail = afstand + tempo.
    case raceTime
    /// Hoofdwaarde = `weekKm`, geen onderliggende run.
    case weeklyVolume
    /// Hoofdwaarde = `weekCount`, geen eenheid nodig.
    case weeklyCount
}

/// Eén persoonlijk record: een run of periode die ergens de beste van z'n soort is.
/// `run` is nil voor records die niet aan één specifieke run hangen (bv. beste week) —
/// de UI toont dan geen doorklik-chevron.
/// `nonisolated`: puur data + pure formatteer-methoden, geconstrueerd/aangeroepen binnen
/// GameStatsStore's Task.detached (en vanuit CelebrationView, dat via een directe
/// UserDefaults-lezing ook geen main-actor-toegang nodig heeft voor deze methoden).
nonisolated struct PersonalRecord: Identifiable {
    let id: String
    let icon: String
    let title: String
    let kind: PersonalRecordKind
    let run: RunWorkout?
    /// Alleen gebruikt door .weeklyVolume/.weeklyCount, die geen onderliggende run hebben.
    let weekLabel: String?
    let weekKm: Double?
    let weekCount: Int?
    /// De onderliggende meetwaarde waarop vergeleken wordt of een toekomstige run dit record
    /// verbetert (bv. km voor afstandsrecords, sec/km voor temporecords) — altijd in km/sec,
    /// eenheid-onafhankelijk, en niet bedoeld voor weergave.
    let metricValue: Double
    /// True als een hogere metricValue beter is (afstand, aantal runs), false als een lagere
    /// beter is (tempo, duur).
    let isHigherBetter: Bool

    /// Hoofdwaarde, afhankelijk van `kind` — hier op het model i.p.v. alleen in de view,
    /// zodat zowel PersonalRecordsView als CelebrationView (de "nieuw record!"-viering)
    /// dezelfde, live eenheid-bewuste formattering hergebruiken i.p.v. 'm te dupliceren.
    func valueText(using unit: DistanceUnit) -> String {
        switch kind {
        case .distance:
            guard let run else { return "" }
            return unit.format(km: run.distanceKm)
        case .pace:
            guard let run else { return "" }
            return unit.formatPace(secPerKm: run.averagePaceSecPerKm)
        case .raceTime:
            guard let run else { return "" }
            return Self.durationString(seconds: run.durationSeconds)
        case .weeklyVolume:
            return unit.format(km: weekKm ?? 0, decimals: 1)
        case .weeklyCount:
            return "\(weekCount ?? 0)x"
        }
    }

    func detailText(using unit: DistanceUnit) -> String {
        switch kind {
        case .distance:
            guard let run else { return "" }
            return run.startDate.formatted(date: .abbreviated, time: .omitted)
        case .pace:
            guard let run else { return "" }
            return "\(unit.format(km: run.distanceKm)) · \(run.startDate.formatted(date: .abbreviated, time: .omitted))"
        case .raceTime:
            guard let run else { return "" }
            return "\(unit.format(km: run.distanceKm)) · \(unit.formatPace(secPerKm: run.averagePaceSecPerKm)) · \(run.startDate.formatted(date: .abbreviated, time: .omitted))"
        case .weeklyVolume, .weeklyCount:
            return weekLabel ?? ""
        }
    }

    /// Duur converteert niet met de afstandseenheid — tijd is tijd, ongeacht km of miles.
    private static func durationString(seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// Alle persoonlijke records + totalen, berekend over de volledige (lifetime) hardloop-
/// geschiedenis — dus bewust niet beperkt tot het rollende venster dat de live
/// GameEngine-scores gebruikt. Zie GameStatsStore voor waar dit vandaan komt.
/// `nonisolated`: puur data + pure berekening, aangeroepen binnen GameStatsStore's
/// Task.detached — cascadeert naar de geneste DistanceRecordDefinition/WeekTotal hieronder.
nonisolated struct PersonalRecords {
    let records: [PersonalRecord]
    /// Altijd in km — PersonalRecordsView rekent zelf om naar de gekozen weergave-eenheid.
    let totalLifetimeKm: Double
    let totalLifetimeRuns: Int

    static func calculate(from runs: [RunWorkout], calendar: Calendar = .current) -> PersonalRecords {
        var records: [PersonalRecord] = []

        if let longest = runs.max(by: { $0.distanceKm < $1.distanceKm }) {
            records.append(PersonalRecord(
                id: "longest",
                icon: "arrow.up.right",
                title: String(localized: "Longest run", comment: "Personal record title"),
                kind: .distance,
                run: longest,
                weekLabel: nil, weekKm: nil, weekCount: nil,
                metricValue: longest.distanceKm,
                isHigherBetter: true
            ))
        }

        // Zelfde conventie als RunStatsSummary.fastestRun: alleen runs van 1+ km, anders kan
        // een kort ruizig stukje met een toevallig extreem tempo de titel "winnen".
        if let fastest = runs.filter({ $0.distanceKm >= 1 }).min(by: { $0.averagePaceSecPerKm < $1.averagePaceSecPerKm }) {
            records.append(PersonalRecord(
                id: "fastest-overall",
                icon: "bolt.fill",
                title: String(localized: "Fastest pace", comment: "Personal record title"),
                kind: .pace,
                run: fastest,
                weekLabel: nil, weekKm: nil, weekCount: nil,
                metricValue: fastest.averagePaceSecPerKm,
                isHigherBetter: false
            ))
        }

        for definition in distanceRecordDefinitions {
            if let best = fastestRun(in: runs, range: definition.range) {
                records.append(PersonalRecord(
                    id: definition.id,
                    icon: "hare.fill",
                    title: definition.title,
                    kind: .raceTime,
                    run: best,
                    weekLabel: nil, weekKm: nil, weekCount: nil,
                    metricValue: best.averagePaceSecPerKm,
                    isHigherBetter: false
                ))
            }
        }

        let weeklyTotals = weeklyTotals(from: runs, calendar: calendar)

        if let bestWeek = weeklyTotals.max(by: { $0.km < $1.km }) {
            records.append(PersonalRecord(
                id: "best-week-volume",
                icon: "flame.fill",
                title: String(localized: "Best week (kilometers)", comment: "Personal record title"),
                kind: .weeklyVolume,
                run: nil,
                weekLabel: bestWeek.label, weekKm: bestWeek.km, weekCount: nil,
                metricValue: bestWeek.km,
                isHigherBetter: true
            ))
        }

        if let busiestWeek = weeklyTotals.max(by: { $0.count < $1.count }) {
            records.append(PersonalRecord(
                id: "best-week-count",
                icon: "calendar",
                title: String(localized: "Most runs in one week", comment: "Personal record title"),
                kind: .weeklyCount,
                run: nil,
                weekLabel: busiestWeek.label, weekKm: nil, weekCount: busiestWeek.count,
                metricValue: Double(busiestWeek.count),
                isHigherBetter: true
            ))
        }

        let totalKm = runs.reduce(0.0) { $0 + $1.distanceKm }
        return PersonalRecords(records: records, totalLifetimeKm: totalKm, totalLifetimeRuns: runs.count)
    }

    // MARK: - Standaardafstanden

    private struct DistanceRecordDefinition {
        let id: String
        let title: String
        /// Marge rond de "officiële" afstand om GPS-afwijking toe te laten — een 5K die
        /// 4,97 km meet (of 5,03 km) moet nog steeds meetellen als 5K-poging.
        let range: ClosedRange<Double>
    }

    private static let distanceRecordDefinitions: [DistanceRecordDefinition] = [
        DistanceRecordDefinition(id: "fastest-5k", title: String(localized: "Fastest 5K", comment: "Personal record title"), range: 4.5...5.5),
        DistanceRecordDefinition(id: "fastest-10k", title: String(localized: "Fastest 10K", comment: "Personal record title"), range: 9.5...10.5),
        DistanceRecordDefinition(id: "fastest-half", title: String(localized: "Fastest Half Marathon", comment: "Personal record title"), range: 20.5...21.7),
        // Marge iets ruimer dan de kortere afstanden — over 42+ km loopt GPS-afwijking
        // in absolute kilometers sneller op dan bij een 5K/10K, ook al is het percentueel
        // vergelijkbaar. Zelfde drempel (42,2 km) als de "Marathon"-badge in BadgeDefinition.
        DistanceRecordDefinition(id: "fastest-marathon", title: String(localized: "Fastest Marathon", comment: "Personal record title"), range: 41.5...43.5)
    ]

    /// Binnen een afstandsband rangschikken we op tempo, niet op ruwe duur — anders zou een
    /// run aan de ondergrens van de band een langere run met beter tempo altijd "verslaan"
    /// puur omdat hij korter duurde. Getoonde duur is gewoon de werkelijke tijd van díe run.
    private static func fastestRun(in runs: [RunWorkout], range: ClosedRange<Double>) -> RunWorkout? {
        runs.filter { range.contains($0.distanceKm) }
            .min { $0.averagePaceSecPerKm < $1.averagePaceSecPerKm }
    }

    // MARK: - Weektotalen

    private struct WeekTotal {
        let label: String
        let km: Double
        let count: Int
    }

    /// Groepeert op kalenderweek (niet het rollende venster van GameEngine — voor "beste week
    /// ooit" is een vaste kalenderweek intuïtiever, zelfde conventie als RunStatsSummary).
    private static func weeklyTotals(from runs: [RunWorkout], calendar: Calendar) -> [WeekTotal] {
        let grouped = Dictionary(grouping: runs) { run in
            calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: run.startDate)
        }
        return grouped.compactMap { components, runsInWeek -> WeekTotal? in
            guard let weekStart = calendar.date(from: components) else { return nil }
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("d MMM yyyy")
            let weekOfLabel = String(localized: "Week of", comment: "Prefix before a date, e.g. 'Week of Mar 12, 2026'")
            return WeekTotal(
                label: "\(weekOfLabel) \(formatter.string(from: weekStart))",
                km: runsInWeek.reduce(0.0) { $0 + $1.distanceKm },
                count: runsInWeek.count
            )
        }
    }
}
