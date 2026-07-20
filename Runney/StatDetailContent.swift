import SwiftUI

/// Welke van de drie substats getapt is — bepaalt welke sheet getoond wordt.
enum StatKind: String, Identifiable {
    case stamina, consistency, speed, level
    var id: String { rawValue }
}

/// Eén regel in het "wat gebeurde er"-blok van de detailsheet.
struct StatDetailRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}

/// Eén onderdeel van de scoreformule (bv. "Runs deze week" of "Streak" binnen Consistentie).
/// `title` is nil als de stat uit één doorlopende curve bestaat (Stamina) — dan wordt geen
/// aparte kop getoond, alleen de rijen zelf.
struct ScoreCurveGroup: Identifiable {
    let id = UUID()
    let title: String?
    let rows: [StatDetailRow]
}

/// Alle content voor de detailsheet van één substat — icoon, score, uitleg, cijfers, tips.
struct StatDetailContent {
    let icon: String
    let color: Color
    let title: String
    /// Wat groot getoond wordt rechtsboven, bv. "87" voor een 0-100 stat of "Lv. 9" voor Level.
    let scoreText: String
    /// 0...1, bepaalt hoe ver de balk gevuld is. Voor de 0-100 stats is dit score/100,
    /// voor Level is dit de XP-voortgang naar het volgende level.
    let progress: Double
    /// True voor de 0-100 stats (stamina/consistentie/snelheid) — dan tonen we referentie-
    /// streepjes op 25/50/75% in de balk. False voor Level, waar dat niet betekenisvol is.
    let showsHundredScale: Bool
    let description: String
    /// De exacte score-formule, rechtstreeks uit GameConstants opgebouwd zodat dit nooit los
    /// kan raken van de werkelijke berekening. Leeg voor Level, die geen curve heeft.
    let scoreBreakdown: [ScoreCurveGroup]
    let rows: [StatDetailRow]
    let tips: [String]

    /// Centrale lookup zodat elk scherm dat een StatKind naar content moet vertalen dezelfde
    /// switch hergebruikt. `distanceUnit` wordt hier doorgegeven i.p.v. gecachet — deze content
    /// wordt telkens vers opgebouwd op het moment dat een sheet opent (zie HomeView/StatsView),
    /// dus een live @AppStorage-lezing bij de aanroeper is hier voldoende, geen aparte
    /// Combine-subscriptie nodig zoals bij de wél-gecachete PersonalRecords.
    static func content(for kind: StatKind, breakdown: GameEngineDebugInfo, distanceUnit: DistanceUnit) -> StatDetailContent {
        switch kind {
        case .stamina: return .stamina(breakdown: breakdown, distanceUnit: distanceUnit)
        case .consistency: return .consistency(breakdown: breakdown)
        case .speed: return .speed(breakdown: breakdown, distanceUnit: distanceUnit)
        case .level: return .level(breakdown: breakdown)
        }
    }
}

extension StatDetailContent {

    static func stamina(breakdown: GameEngineDebugInfo, distanceUnit: DistanceUnit) -> StatDetailContent {
        var rows = [
            StatDetailRow(label: String(localized: "Effective weekly volume", comment: "Stamina detail row"), value: distanceUnit.format(km: breakdown.effectiveStaminaVolumeKm, decimals: 1))
        ]
        rows += breakdown.recentWeeks.map { week in
            StatDetailRow(
                label: weekLabel(weeksAgo: week.weeksAgo),
                value: "\(distanceUnit.format(km: week.km, decimals: 1)) · \(week.runCount)x"
            )
        }

        return StatDetailContent(
            icon: "flame.fill",
            color: CozyPalette.stamina,
            title: String(localized: "Stamina", comment: "Substat name"),
            scoreText: "\(breakdown.stats.stamina)/100",
            progress: Double(breakdown.stats.stamina) / 100,
            showsHundredScale: true,
            description: String(localized: "Stamina shows how much you've been running lately. We look at your average weekly volume over the last 4 weeks, with more recent weeks weighing more heavily — so your score doesn't crash after a single rest week.", comment: "Stamina description"),
            scoreBreakdown: [ScoreCurveGroup(title: nil, rows: staminaScoreCurveRows(distanceUnit: distanceUnit))],
            rows: rows,
            tips: [
                String(localized: "Build up your weekly kilometers gradually.", comment: "Stamina tip"),
                String(localized: "One rest week is fine — your score only drops slowly along with it.", comment: "Stamina tip"),
                String(localized: "From 50 km per week you're at the maximum score.", comment: "Stamina tip")
            ]
        )
    }

    static func consistency(breakdown: GameEngineDebugInfo) -> StatDetailContent {
        let rows = [
            StatDetailRow(label: String(localized: "Runs this week", comment: "Consistency detail row"), value: "\(breakdown.runsThisWeek)"),
            StatDetailRow(label: String(localized: "Streak", comment: "Consistency detail row"), value: breakdown.streakWeeks == 1 ? String(localized: "1 week", comment: "Streak duration") : String(format: String(localized: "%d weeks", comment: "Streak duration"), breakdown.streakWeeks))
        ]

        return StatDetailContent(
            icon: "calendar",
            color: CozyPalette.consistency,
            title: String(localized: "Consistency", comment: "Substat name"),
            scoreText: "\(breakdown.stats.consistency)/100",
            progress: Double(breakdown.stats.consistency) / 100,
            showsHundredScale: true,
            description: String(localized: "Consistency rewards regularity. Half comes from how often you run this week, the other half from how many weeks in a row you keep it up.", comment: "Consistency description"),
            scoreBreakdown: [
                ScoreCurveGroup(title: String(localized: "Runs this week (max 40)", comment: "Score breakdown section title"), rows: consistencyWeekCheckRows()),
                ScoreCurveGroup(title: String(localized: "Streak (max 60)", comment: "Score breakdown section title"), rows: consistencyStreakCurveRows())
            ],
            rows: rows,
            tips: [
                String(localized: "Running 3 or more times a week gives the maximum weekly points.", comment: "Consistency tip"),
                String(localized: "Every consecutive week builds your streak further — at 12 weeks in a row you're at the maximum.", comment: "Consistency tip"),
                String(localized: "This week only counts once you hit it, but it doesn't break your streak while it's still ongoing — only a missed, completed week does that.", comment: "Consistency tip")
            ]
        )
    }

    static func speed(breakdown: GameEngineDebugInfo, distanceUnit: DistanceUnit) -> StatDetailContent {
        let rows = [
            StatDetailRow(label: String(localized: "Fastest pace (30 days)", comment: "Speed detail row"), value: paceString(breakdown.fastestQualifyingPaceSecPerKm, distanceUnit: distanceUnit)),
            StatDetailRow(label: String(localized: "Tempo run last 7 days", comment: "Speed detail row"), value: breakdown.hasTempoRunLast7Days ? String(localized: "Yes", comment: "Boolean value") : String(localized: "No", comment: "Boolean value")),
            StatDetailRow(label: String(localized: "Interval last 7 days", comment: "Speed detail row"), value: breakdown.hasIntervalRunLast7Days ? String(localized: "Yes", comment: "Boolean value") : String(localized: "No", comment: "Boolean value"))
        ]

        return StatDetailContent(
            icon: "bolt.fill",
            color: CozyPalette.speed,
            title: String(localized: "Speed", comment: "Substat name"),
            scoreText: "\(breakdown.stats.speed)/100",
            progress: Double(breakdown.stats.speed) / 100,
            showsHundredScale: true,
            description: String(localized: "Speed combines your best pace from the last 30 days with bonus points for tempo runs and interval training — that bonus stays active for 7 days after such a run.", comment: "Speed description"),
            scoreBreakdown: [
                ScoreCurveGroup(title: String(localized: "Pace (max 60)", comment: "Score breakdown section title"), rows: speedPaceCurveRows(distanceUnit: distanceUnit)),
                ScoreCurveGroup(title: String(localized: "Bonus (max 40)", comment: "Score breakdown section title"), rows: speedBonusRows())
            ],
            rows: rows,
            tips: [
                String(localized: "A faster best time over 5 km directly raises your base score.", comment: "Speed tip"),
                String(localized: "A continuous tempo run of 20+ minutes gives a bonus.", comment: "Speed tip"),
                String(localized: "An interval training with varying pace also gives a bonus.", comment: "Speed tip")
            ]
        )
    }

    static func level(breakdown: GameEngineDebugInfo) -> StatDetailContent {
        let stats = breakdown.stats
        var rows = [
            StatDetailRow(label: String(localized: "Title", comment: "Level detail row"), value: stats.levelTitle),
            StatDetailRow(label: String(localized: "Total XP", comment: "Level detail row"), value: stats.totalXP.formatted())
        ]
        if stats.xpNeededForNextLevel > 0 {
            rows.append(StatDetailRow(label: String(localized: "XP in this level", comment: "Level detail row"), value: "\(stats.xpIntoCurrentLevel.formatted()) / \(stats.xpNeededForNextLevel.formatted())"))
        } else {
            rows.append(StatDetailRow(label: String(localized: "Status", comment: "Level detail row"), value: String(localized: "Highest level reached", comment: "Shown when max level is reached")))
        }
        rows.append(StatDetailRow(label: String(localized: "Counts since", comment: "Level detail row"), value: breakdown.appInstallDate.formatted(date: .abbreviated, time: .omitted)))

        return StatDetailContent(
            icon: "star.fill",
            color: CozyPalette.level,
            title: String(localized: "Level", comment: "Substat name"),
            scoreText: "Lv. \(stats.level)",
            progress: stats.levelProgress,
            showsHundredScale: false,
            description: String(localized: "Your level grows by running kilometers — every kilometer earns a fixed amount of XP. Unlike the three stats above, your level never drops: it's a permanent reflection of what you've built up since you started using the app.", comment: "Level description"),
            scoreBreakdown: [],
            rows: rows,
            tips: [
                String(localized: "Every kilometer you run earns XP, regardless of pace.", comment: "Level tip"),
                String(localized: "Runs from before you first opened the app don't count.", comment: "Level tip"),
                String(localized: "Every level has its own name and requires a bit more XP than the last.", comment: "Level tip")
            ]
        )
    }

    /// Locale-bewust: geeft "This week"/"1 week ago"/"X weeks ago" — geen losse vertaling
    /// per geval nodig dankzij de aparte enkelvoud/meervoud-strings.
    private static func weekLabel(weeksAgo: Int) -> String {
        if weeksAgo == 0 { return String(localized: "This week", comment: "Week label, current week") }
        if weeksAgo == 1 { return String(localized: "1 week ago", comment: "Week label") }
        return String(format: String(localized: "%d weeks ago", comment: "Week label"), weeksAgo)
    }

    // MARK: - Score-curves, rechtstreeks uit GameConstants opgebouwd

    /// Anker uit GameConstants.staminaScoreCurve. Alleen het laatste punt krijgt een "+",
    /// want interpolate() capt daarboven op de maximale score — alles ertussen loopt lineair.
    /// De ankerpunten zelf staan in km in GameConstants (score-logica blijft altijd in km),
    /// maar hier rekenen we ze om naar de gekozen weergave-eenheid.
    private static func staminaScoreCurveRows(distanceUnit: DistanceUnit) -> [StatDetailRow] {
        let curve = GameConstants.staminaScoreCurve
        return curve.enumerated().map { index, point in
            let isLast = index == curve.count - 1
            let displayValue = Int(distanceUnit.convert(fromKm: point.km).rounded())
            let label = isLast
                ? String(format: String(localized: "%d+ %@/week", comment: "e.g. '50+ km/week'"), displayValue, distanceUnit.abbreviation)
                : String(format: String(localized: "%d %@/week", comment: "e.g. '5 km/week'"), displayValue, distanceUnit.abbreviation)
            return StatDetailRow(label: label, value: String(format: String(localized: "%d points", comment: "Score curve points"), Int(point.score)))
        }
    }

    /// GameConstants.consistencyWeekCheckScores is een discrete stappen-tabel (geen
    /// interpolatie, zie GameEngine.scoreForRunCount) — vertaalt zich dus 1-op-1 naar rijen.
    private static func consistencyWeekCheckRows() -> [StatDetailRow] {
        let table = GameConstants.consistencyWeekCheckScores
        return table.enumerated().map { index, entry in
            let isLast = index == table.count - 1
            let label: String
            if isLast {
                label = String(format: String(localized: "%d+ runs", comment: "e.g. '3+ runs'"), entry.runs)
            } else if entry.runs == 1 {
                label = String(localized: "1 run", comment: "Score curve label")
            } else {
                label = String(format: String(localized: "%d runs", comment: "e.g. '2 runs'"), entry.runs)
            }
            return StatDetailRow(label: label, value: String(format: String(localized: "%d points", comment: "Score curve points"), Int(entry.score)))
        }
    }

    /// Anker uit GameConstants.consistencyStreakScoreCurve, lineair geïnterpoleerd tussen de
    /// punten — zelfde "+" op het laatste punt als bij Stamina.
    private static func consistencyStreakCurveRows() -> [StatDetailRow] {
        let curve = GameConstants.consistencyStreakScoreCurve
        return curve.enumerated().map { index, point in
            let isLast = index == curve.count - 1
            let weeks = Int(point.weeks)
            let label: String
            if isLast {
                label = String(format: String(localized: "%d+ weeks", comment: "e.g. '12+ weeks'"), weeks)
            } else if weeks == 1 {
                label = String(localized: "1 week", comment: "Score curve label")
            } else {
                label = String(format: String(localized: "%d weeks", comment: "e.g. '4 weeks'"), weeks)
            }
            return StatDetailRow(label: label, value: String(format: String(localized: "%d points", comment: "Score curve points"), Int(point.score)))
        }
    }

    /// Anker uit GameConstants.speedPaceRatingCurve — sneller tempo (lager sec/km) geeft een
    /// hogere score, dus het éérste punt (snelste tempo) is hier de bovengrens ("of sneller")
    /// en het láátste punt (traagste) de ondergrens ("of trager").
    private static func speedPaceCurveRows(distanceUnit: DistanceUnit) -> [StatDetailRow] {
        let curve = GameConstants.speedPaceRatingCurve
        return curve.enumerated().map { index, point in
            let pace = distanceUnit.formatPace(secPerKm: point.paceSecPerKm)
            let label: String
            if index == 0 {
                label = String(format: String(localized: "%@ or faster", comment: "e.g. '4:15/km or faster'"), pace)
            } else if index == curve.count - 1 {
                label = String(format: String(localized: "%@ or slower", comment: "e.g. '8:00/km or slower'"), pace)
            } else {
                label = pace
            }
            return StatDetailRow(label: label, value: String(format: String(localized: "%d points", comment: "Score curve points"), Int(point.score)))
        }
    }

    /// GameConstants.speedBonusPointsPerType, één rij per type — geen curve, gewoon een vast
    /// bedrag per type binnen het bonusvenster (GameConstants.speedBonusWindowDays).
    private static func speedBonusRows() -> [StatDetailRow] {
        let points = Int(GameConstants.speedBonusPointsPerType)
        let pointsText = String(format: String(localized: "+%d points", comment: "e.g. '+20 points'"), points)
        return [
            StatDetailRow(label: String(localized: "Tempo run (last 7 days)", comment: "Speed bonus row"), value: pointsText),
            StatDetailRow(label: String(localized: "Interval training (last 7 days)", comment: "Speed bonus row"), value: pointsText)
        ]
    }

    private static func paceString(_ paceSecPerKm: Double?, distanceUnit: DistanceUnit) -> String {
        guard let pace = paceSecPerKm, pace > 0 else { return "-" }
        return distanceUnit.formatPace(secPerKm: pace)
    }
}
