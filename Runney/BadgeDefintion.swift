import SwiftUI

/// Welke databronnen een badge tot z'n beschikking heeft bij het evalueren. Twee aparte
/// bronnen omdat ze een andere prijs/volledigheid-afweging hebben (zie HealthKitManager):
/// lifetimeRuns is compleet maar ongeclassificeerd, recentClassifiedRuns is geclassificeerd
/// maar beperkt tot een venster.
/// `nonisolated`: puur data, geconstrueerd binnen GameStatsStore's Task.detached.
nonisolated struct BadgeEvaluationContext {
    /// Alle runs ooit opgehaald, zonder tempo/interval-classificatie. Gebruik dit voor alles
    /// wat puur op afstand, datum, of cumulatief volume draait.
    let lifetimeRuns: [RunWorkout]
    /// Het recente venster mét classificatie (effortType is hier betrouwbaar; buiten dit
    /// venster staat effortType altijd op .none, ook als de run wel degelijk een tempoloop
    /// was — HealthKitManager classificeert bewust niet de volledige historie).
    /// Bekende beperking: een effort-badge als "Eerste Tempoloop" is hierdoor impliciet
    /// "eerste sinds we zijn gaan classificeren", niet per se de allereerste ooit.
    let recentClassifiedRuns: [RunWorkout]
}

/// Groepering voor het Badges-scherm — puur presentatie, geen invloed op de evaluatie zelf.
/// Bewust expliciet per badge ingevuld i.p.v. afgeleid uit welke factory gebruikt is, want
/// sommige factories (effortMilestone) worden voor meerdere categorieën gebruikt (bv.
/// "Eerste Tempoloop" hoort bij Inspanning, "Vroege Vogel" bij Bijzonder).
/// `nonisolated`: puur data, geconstrueerd binnen GameStatsStore's Task.detached.
nonisolated enum BadgeCategory: String, CaseIterable, Identifiable, Hashable {
    case distance, cumulative, pace, effort, streak, level, special, yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .distance: return String(localized: "Distance", comment: "Badge category")
        case .cumulative: return String(localized: "Cumulative", comment: "Badge category")
        case .pace: return String(localized: "Pace", comment: "Badge category")
        case .effort: return String(localized: "Effort", comment: "Badge category")
        case .streak: return String(localized: "Streak", comment: "Badge category")
        case .level: return String(localized: "Level", comment: "Badge category")
        case .special: return String(localized: "Special", comment: "Badge category")
        case .yearly: return String(localized: "This Year", comment: "Badge category")
        }
    }
}

/// Eén badge: wat 'm is, hoe hij eruitziet, en hoe je 'm behaalt. `evaluate` geeft de datum
/// terug waarop de badge voor het eerst behaald is, of nil als hij nog niet behaald is —
/// zo hebben we meteen ook de "wanneer" gratis.
/// `nonisolated`: puur data (incl. de `evaluate`-closure en `static let all`), aangeroepen/
/// geconstrueerd binnen GameStatsStore's Task.detached — lost de 'all'/'evaluate'-fouten op.
nonisolated struct BadgeDefinition: Identifiable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let color: Color
    let category: BadgeCategory
    let evaluate: (BadgeEvaluationContext) -> Date?
}

/// `nonisolated`: zelfde reden als bij GameEngine's extensies — een extensie erft niet
/// automatisch de nonisolated-status van de hoofddeclaratie, zelfs niet binnen hetzelfde
/// bestand. Dit voorkomt precies de "static property 'all' cannot be accessed"-fout.
nonisolated extension BadgeDefinition {

    /// Badge voor de eerste keer dat één enkele run een bepaalde afstand haalt.
    static func distanceMilestone(id: String, km: Double, title: String, description: String, icon: String, category: BadgeCategory) -> BadgeDefinition {
        BadgeDefinition(id: id, title: title, description: description, icon: icon, color: CozyPalette.stamina, category: category) { context in
            context.lifetimeRuns.filter { $0.distanceKm >= km }
                .min { $0.startDate < $1.startDate }?
                .startDate
        }
    }

    /// Badge voor het bereiken van een cumulatief totaal aantal kilometers, all-time.
    static func cumulativeMilestone(id: String, km: Double, title: String, description: String, icon: String, category: BadgeCategory) -> BadgeDefinition {
        BadgeDefinition(id: id, title: title, description: description, icon: icon, color: CozyPalette.level, category: category) { context in
            let sorted = context.lifetimeRuns.sorted { $0.startDate < $1.startDate }
            var cumulative = 0.0
            for run in sorted {
                cumulative += run.distanceKm
                if cumulative >= km { return run.startDate }
            }
            return nil
        }
    }

    /// Badge voor de eerste run die aan een bepaald predicaat voldoet. Flexibel genoeg voor
    /// zowel effort-type badges (tempoloop/interval) als tijdstip/gedrag-badges (vroege vogel,
    /// weekend) — vandaar dat category hier geen vaste standaardwaarde heeft.
    static func effortMilestone(
        id: String, title: String, description: String, icon: String, category: BadgeCategory,
        matches: @escaping (RunWorkout) -> Bool
    ) -> BadgeDefinition {
        BadgeDefinition(id: id, title: title, description: description, icon: icon, color: CozyPalette.speed, category: category) { context in
            // Bewust recentClassifiedRuns, niet lifetimeRuns: effortType is buiten dit
            // venster altijd .none, dus lifetimeRuns zou hier nooit iets matchen.
            context.recentClassifiedRuns.filter(matches)
                .min { $0.startDate < $1.startDate }?
                .startDate
        }
    }

    /// Badge voor de eerste run (van minstens 1 km, om ruis uit te sluiten) onder een bepaald tempo.
    static func paceMilestone(id: String, paceSecPerKm: Double, title: String, description: String, icon: String, category: BadgeCategory) -> BadgeDefinition {
        BadgeDefinition(id: id, title: title, description: description, icon: icon, color: CozyPalette.speed, category: category) { context in
            context.lifetimeRuns.filter { $0.distanceKm >= 1 && $0.averagePaceSecPerKm > 0 && $0.averagePaceSecPerKm <= paceSecPerKm }
                .min { $0.startDate < $1.startDate }?
                .startDate
        }
    }

    /// Badge voor het voor het eerst bereiken van een streak van N weken. Een streak kan
    /// resetten, dus (anders dan afstand/cumulatief) is dit niet in één keer af te leiden —
    /// we simuleren dag voor dag terug vanaf de eerste run tot de drempel gehaald werd.
    /// Prima snel genoeg voor de hoeveelheid runs die een individuele gebruiker heeft.
    static func streakMilestone(id: String, weeks: Int, title: String, description: String, icon: String, category: BadgeCategory) -> BadgeDefinition {
        BadgeDefinition(id: id, title: title, description: description, icon: icon, color: CozyPalette.consistency, category: category) { context in
            let runs = context.lifetimeRuns
            guard let earliest = runs.map(\.startDate).min() else { return nil }
            let calendar = Calendar.current
            let now = Date()
            var cursor = earliest
            var safety = 0
            while cursor <= now && safety < 1500 {
                let streakWeeks = GameEngine.debugBreakdown(from: runs, now: cursor, calendar: calendar).streakWeeks
                if streakWeeks >= weeks { return cursor }
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? now
                safety += 1
            }
            return nil
        }
    }

    /// Badge voor het bereiken van een level. XP is cumulatief en groeit nooit terug, dus dit
    /// kan efficiënt in één keer: gewoon doorlopen tot de XP-drempel van dat level gehaald is.
    static func levelMilestone(id: String, level: Int, title: String, description: String, icon: String, category: BadgeCategory) -> BadgeDefinition {
        BadgeDefinition(id: id, title: title, description: description, icon: icon, color: CozyPalette.level, category: category) { context in
            guard let threshold = GameConstants.levelThresholds.first(where: { $0.level == level }) else { return nil }
            let eligible = context.lifetimeRuns
                .filter { $0.startDate >= AppInstallDate.value }
                .sorted { $0.startDate < $1.startDate }

            var cumulativeXP = 0.0
            for run in eligible {
                cumulativeXP += run.distanceKm * GameConstants.xpPerKm
                if Int(cumulativeXP.rounded()) >= threshold.xpRequired {
                    return run.startDate
                }
            }
            return nil
        }
    }

    /// Badge voor twee runs op één kalenderdag. Geen bestaande factory past hierop (die kijken
    /// allemaal naar één run of een lopend venster) — dit groepeert de volledige runs-lijst per
    /// dag en zoekt de vroegste dag met 2+ runs. Als "wanneer behaald" geven we het moment van
    /// de tweede run die dag terug, niet het begin van de dag — dat is het exacte moment waarop
    /// aan de voorwaarde voldaan werd.
    static let doubleDay = BadgeDefinition(
        id: "double-day", title: String(localized: "Double Day", comment: "Badge title"),
        description: String(localized: "Complete two runs on the same day.", comment: "Badge description"),
        icon: "2.circle.fill", color: CozyPalette.consistency, category: .special
    ) { context in
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: context.lifetimeRuns) { calendar.startOfDay(for: $0.startDate) }
        guard let earliestQualifyingDay = byDay.filter({ $0.value.count >= 2 }).keys.min() else { return nil }
        let runsThatDay = byDay[earliestQualifyingDay]!.sorted { $0.startDate < $1.startDate }
        return runsThatDay.count >= 2 ? runsThatDay[1].startDate : nil
    }

    /// Badge voor een run na een pauze van 21+ dagen sinds de vorige — bewust positief geframed
    /// (een "welkom terug"-viering) i.p.v. de streak simpelweg te laten breken zonder iets terug
    /// te geven. Scant de chronologisch gesorteerde historie op de eerste kloof van 21+ dagen.
    static let comeback = BadgeDefinition(
        id: "comeback", title: String(localized: "The Comeback", comment: "Badge title"),
        description: String(localized: "Return with a new run after at least 21 days of rest.", comment: "Badge description"),
        icon: "arrow.uturn.backward.circle.fill", color: CozyPalette.consistency, category: .special
    ) { context in
        let sorted = context.lifetimeRuns.sorted { $0.startDate < $1.startDate }
        guard sorted.count >= 2 else { return nil }
        for i in 1..<sorted.count {
            let gapDays = Calendar.current.dateComponents([.day], from: sorted[i - 1].startDate, to: sorted[i].startDate).day ?? 0
            if gapDays >= 21 { return sorted[i].startDate }
        }
        return nil
    }

    /// Eerste *cumulatieve* effort-badge (i.p.v. "eerste keer") — telt het totaal aantal
    /// tempolopen. Bewust op recentClassifiedRuns, net als effortMilestone: effortType is
    /// buiten dat venster altijd .none, dus een telling op lifetimeRuns zou de 10 nooit halen.
    static let tempoTrainer = BadgeDefinition(
        id: "tempo-trainer", title: String(localized: "Tempo Trainer", comment: "Badge title"),
        description: String(localized: "Complete a total of 10 tempo runs.", comment: "Badge description"),
        icon: "arrow.triangle.2.circlepath", color: CozyPalette.speed, category: .effort
    ) { context in
        let tempoRuns = context.recentClassifiedRuns
            .filter { $0.effortType.isTempo }
            .sorted { $0.startDate < $1.startDate }
        return tempoRuns.count >= 10 ? tempoRuns[9].startDate : nil
    }

    /// Badge voor het behalen van een cumulatief aantal kilometers binnen één kalenderjaar
    /// (i.p.v. all-time zoals cumulativeMilestone). Zoekt het vroegste jaar in de hele
    /// geschiedenis waarin de drempel gehaald werd — niet per se "het huidige jaar" — zodat
    /// de badge permanent behaald blijft en niet weer op slot springt zodra het kalenderjaar
    /// omslaat. `months` beperkt optioneel tot een subset van maanden (voor de seizoensbadges);
    /// nil = het hele jaar.
    static func yearlyDistanceMilestone(
        id: String, km: Double, title: String, description: String, icon: String, category: BadgeCategory,
        months: Set<Int>? = nil
    ) -> BadgeDefinition {
        BadgeDefinition(id: id, title: title, description: description, icon: icon, color: CozyPalette.level, category: category) { context in
            let calendar = Calendar.current
            let relevantRuns = context.lifetimeRuns.filter { run in
                guard let months else { return true }
                return months.contains(calendar.component(.month, from: run.startDate))
            }
            let byYear = Dictionary(grouping: relevantRuns) { calendar.component(.year, from: $0.startDate) }
            for year in byYear.keys.sorted() {
                let runsInYear = (byYear[year] ?? []).sorted { $0.startDate < $1.startDate }
                var cumulative = 0.0
                for run in runsInYear {
                    cumulative += run.distanceKm
                    if cumulative >= km { return run.startDate }
                }
            }
            return nil
        }
    }

    /// Zelfde "per kalenderjaar, niet per se het huidige"-aanpak, maar dan op aantal runs
    /// i.p.v. kilometers.
    static func yearlyRunCountMilestone(id: String, count: Int, title: String, description: String, icon: String, category: BadgeCategory) -> BadgeDefinition {
        BadgeDefinition(id: id, title: title, description: description, icon: icon, color: CozyPalette.consistency, category: category) { context in
            let calendar = Calendar.current
            let byYear = Dictionary(grouping: context.lifetimeRuns) { calendar.component(.year, from: $0.startDate) }
            for year in byYear.keys.sorted() {
                let runsInYear = (byYear[year] ?? []).sorted { $0.startDate < $1.startDate }
                if runsInYear.count >= count {
                    return runsInYear[count - 1].startDate
                }
            }
            return nil
        }
    }

    /// Badge voor het lopen in elke maand van hetzelfde kalenderjaar. Zelfde
    /// permanentie-aanpak: doorloopt elk jaar chronologisch en stopt bij het eerste jaar
    /// waarin alle 12 maanden voorkomen.
    static let allTwelveMonths = BadgeDefinition(
        id: "year-all-months", title: String(localized: "Twelve for Twelve", comment: "Badge title"),
        description: String(localized: "Run at least once in every month of a calendar year.", comment: "Badge description"),
        icon: "calendar.circle.fill", color: CozyPalette.consistency, category: .yearly
    ) { context in
        let calendar = Calendar.current
        let byYear = Dictionary(grouping: context.lifetimeRuns) { calendar.component(.year, from: $0.startDate) }
        for year in byYear.keys.sorted() {
            let runsInYear = (byYear[year] ?? []).sorted { $0.startDate < $1.startDate }
            var monthsSeen: Set<Int> = []
            for run in runsInYear {
                monthsSeen.insert(calendar.component(.month, from: run.startDate))
                if monthsSeen.count == 12 { return run.startDate }
            }
        }
        return nil
    }

    static let all: [BadgeDefinition] = [
        .distanceMilestone(id: "run-5k", km: 5, title: String(localized: "First 5K", comment: "Badge title"), description: String(localized: "Run 5 kilometers in one go.", comment: "Badge description"), icon: "figure.run", category: .distance),
        .distanceMilestone(id: "run-10k", km: 10, title: String(localized: "First 10K", comment: "Badge title"), description: String(localized: "Run 10 kilometers in one go.", comment: "Badge description"), icon: "flame.fill", category: .distance),
        .distanceMilestone(id: "run-15k", km: 15, title: String(localized: "First 15K", comment: "Badge title"), description: String(localized: "Run 15 kilometers in one go.", comment: "Badge description"), icon: "bolt.fill", category: .distance),
        .distanceMilestone(id: "run-half", km: 21.1, title: String(localized: "Half Marathon", comment: "Badge title"), description: String(localized: "Run 21.1 kilometers in one go.", comment: "Badge description"), icon: "medal.fill", category: .distance),
        .distanceMilestone(id: "run-marathon", km: 42.2, title: String(localized: "Marathon", comment: "Badge title"), description: String(localized: "Run the full 42.2 kilometers in one go.", comment: "Badge description"), icon: "crown.fill", category: .distance),
        .distanceMilestone(id: "run-1k", km: 1, title: String(localized: "First Kilometer", comment: "Badge title"), description: String(localized: "Run your very first full kilometer.", comment: "Badge description"), icon: "figure.walk", category: .distance),
        .distanceMilestone(id: "run-20k", km: 20, title: String(localized: "20K Runner", comment: "Badge title"), description: String(localized: "Run 20 kilometers in one go.", comment: "Badge description"), icon: "shoeprints.fill", category: .distance),
        .distanceMilestone(id: "run-50k", km: 50, title: String(localized: "Ultra Runner", comment: "Badge title"), description: String(localized: "Run 50 kilometers in one go — ultra territory.", comment: "Badge description"), icon: "mountain.2.fill", category: .distance),

        .cumulativeMilestone(id: "total-50", km: 50, title: String(localized: "50 km Club", comment: "Badge title"), description: String(localized: "Run a total of 50 kilometers.", comment: "Badge description"), icon: "star.fill", category: .cumulative),
        .cumulativeMilestone(id: "total-100", km: 100, title: String(localized: "100 km Club", comment: "Badge title"), description: String(localized: "Run a total of 100 kilometers.", comment: "Badge description"), icon: "star.circle.fill", category: .cumulative),
        .cumulativeMilestone(id: "total-250", km: 250, title: String(localized: "250 km Club", comment: "Badge title"), description: String(localized: "Run a total of 250 kilometers.", comment: "Badge description"), icon: "rosette", category: .cumulative),
        .cumulativeMilestone(id: "total-500", km: 500, title: String(localized: "500 km Club", comment: "Badge title"), description: String(localized: "Run a total of 500 kilometers.", comment: "Badge description"), icon: "trophy.fill", category: .cumulative),
        .cumulativeMilestone(id: "total-1000", km: 1000, title: String(localized: "1000 km Club", comment: "Badge title"), description: String(localized: "A total of 1000 kilometers — a true endurance runner.", comment: "Badge description"), icon: "sparkles", category: .cumulative),
        .cumulativeMilestone(id: "total-2000", km: 2000, title: String(localized: "2000 km Club", comment: "Badge title"), description: String(localized: "Run a total of 2000 kilometers.", comment: "Badge description"), icon: "chart.line.uptrend.xyaxis", category: .cumulative),
        .cumulativeMilestone(id: "total-5000", km: 5000, title: String(localized: "5000 km Club", comment: "Badge title"), description: String(localized: "A total of 5000 kilometers — you've basically crossed a continent.", comment: "Badge description"), icon: "globe.europe.africa.fill", category: .cumulative),

        .effortMilestone(id: "first-tempo", title: String(localized: "First Tempo Run", comment: "Badge title"), description: String(localized: "Complete your first tempo run.", comment: "Badge description"), icon: "bolt.fill", category: .effort) { $0.effortType.isTempo },
        .effortMilestone(id: "first-interval", title: String(localized: "First Interval Training", comment: "Badge title"), description: String(localized: "Complete your first interval training.", comment: "Badge description"), icon: "arrow.left.arrow.right", category: .effort) { $0.effortType.isInterval },
        .tempoTrainer,

        .paceMilestone(id: "pace-500", paceSecPerKm: 300, title: String(localized: "Speedy Five", comment: "Badge title"), description: String(localized: "Run at least 1 km faster than 5:00/km.", comment: "Badge description"), icon: "hare.fill", category: .pace),
        .paceMilestone(id: "goal-pace", paceSecPerKm: GameConstants.goalPaceSecPerKm, title: String(localized: "On Pace", comment: "Badge title"), description: String(localized: "Run at least 1 km at or faster than the goal pace of 4:00/km.", comment: "Badge description"), icon: "bolt.circle.fill", category: .pace),

        .streakMilestone(id: "streak-4", weeks: 4, title: String(localized: "Four in a Row", comment: "Badge title"), description: String(localized: "Keep your consistency going for 4 weeks in a row.", comment: "Badge description"), icon: "checkmark.seal.fill", category: .streak),
        .streakMilestone(id: "streak-26", weeks: 26, title: String(localized: "Half a Year Strong", comment: "Badge title"), description: String(localized: "Keep your consistency going for 26 weeks in a row.", comment: "Badge description"), icon: "checkmark.seal.fill", category: .streak),

        .levelMilestone(id: "level-5", level: 5, title: String(localized: "Distance Apprentice", comment: "Badge title"), description: String(localized: "Reach level 5.", comment: "Badge description"), icon: "flag.fill", category: .level),
        .levelMilestone(id: "level-20", level: 20, title: String(localized: "Max Level", comment: "Badge title"), description: String(localized: "Reach the highest level: Half Marathon Champion.", comment: "Badge description"), icon: "flag.checkered", category: .level),

        .effortMilestone(id: "early-bird", title: String(localized: "Early Bird", comment: "Badge title"), description: String(localized: "Complete a run that starts before 7:00 AM.", comment: "Badge description"), icon: "sunrise.fill", category: .special) {
            Calendar.current.component(.hour, from: $0.startDate) < 7
        },
        .effortMilestone(id: "night-owl", title: String(localized: "Night Owl", comment: "Badge title"), description: String(localized: "Complete a run that starts after 9:00 PM.", comment: "Badge description"), icon: "moon.stars.fill", category: .special) {
            Calendar.current.component(.hour, from: $0.startDate) >= 21
        },
        .effortMilestone(id: "weekend-warrior", title: String(localized: "Weekend Warrior", comment: "Badge title"), description: String(localized: "Complete a run on the weekend.", comment: "Badge description"), icon: "calendar.badge.clock", category: .special) {
            // Calendar telt zondag altijd als 1 en zaterdag als 7, ongeacht de locale-instelling
            // van de eerste weekdag — dus dit klopt ook al staat de kalender op maandag-start.
            let weekday = Calendar.current.component(.weekday, from: $0.startDate)
            return weekday == 1 || weekday == 7
        },
        .effortMilestone(id: "new-years-run", title: String(localized: "New Year's Run", comment: "Badge title"), description: String(localized: "Kick off the year with a run on January 1st.", comment: "Badge description"), icon: "party.popper.fill", category: .special) {
            let components = Calendar.current.dateComponents([.month, .day], from: $0.startDate)
            return components.month == 1 && components.day == 1
        },
        .doubleDay,
        .comeback,

        // MARK: - Dit Jaar (10) — kijkt per kalenderjaar, niet per se het huidige (zie
        // yearlyDistanceMilestone/yearlyRunCountMilestone voor waarom dat belangrijk is).

        .yearlyDistanceMilestone(id: "year-500km", km: 500, title: String(localized: "500 km in a Year", comment: "Badge title"), description: String(localized: "Run a total of 500 kilometers in one calendar year.", comment: "Badge description"), icon: "calendar", category: .yearly),
        .yearlyDistanceMilestone(id: "year-1000km", km: 1000, title: String(localized: "1000 km in a Year", comment: "Badge title"), description: String(localized: "Run a total of 1000 kilometers in one calendar year.", comment: "Badge description"), icon: "calendar.badge.clock", category: .yearly),
        .yearlyDistanceMilestone(id: "year-2000km", km: 2000, title: String(localized: "2000 km in a Year", comment: "Badge title"), description: String(localized: "Run a total of 2000 kilometers in one calendar year — an impressive annual volume.", comment: "Badge description"), icon: "calendar.badge.exclamationmark", category: .yearly),

        .yearlyRunCountMilestone(id: "year-50-runs", count: 50, title: String(localized: "Fifty Runs in a Year", comment: "Badge title"), description: String(localized: "Complete 50 runs within one calendar year.", comment: "Badge description"), icon: "figure.run.circle", category: .yearly),
        .yearlyRunCountMilestone(id: "year-100-runs", count: 100, title: String(localized: "A Hundred Runs in a Year", comment: "Badge title"), description: String(localized: "Complete 100 runs within one calendar year.", comment: "Badge description"), icon: "figure.run.circle.fill", category: .yearly),

        .allTwelveMonths,

        .yearlyDistanceMilestone(id: "year-spring", km: 100, title: String(localized: "Spring Runner", comment: "Badge title"), description: String(localized: "Run 100 kilometers between March and May of the same year.", comment: "Badge description"), icon: "leaf.fill", category: .yearly, months: [3, 4, 5]),
        .yearlyDistanceMilestone(id: "year-summer", km: 100, title: String(localized: "Summer Warrior", comment: "Badge title"), description: String(localized: "Run 100 kilometers between June and August of the same year.", comment: "Badge description"), icon: "sun.max.fill", category: .yearly, months: [6, 7, 8]),
        .yearlyDistanceMilestone(id: "year-autumn", km: 100, title: String(localized: "Autumn Persister", comment: "Badge title"), description: String(localized: "Run 100 kilometers between September and November of the same year.", comment: "Badge description"), icon: "wind", category: .yearly, months: [9, 10, 11]),
        // Winter loopt hier bewust over december/januari/februari van hetzelfde kalenderjaar
        // (dus niet de meteorologisch kloppende december-t/m-februari-overgang) — simpeler en
        // consistent met de "per kalenderjaar"-opzet van de rest van deze categorie.
        .yearlyDistanceMilestone(id: "year-winter", km: 100, title: String(localized: "Winter Toughness", comment: "Badge title"), description: String(localized: "Run 100 kilometers in December, January, or February of the same year.", comment: "Badge description"), icon: "snowflake", category: .yearly, months: [12, 1, 2])
    ]
}

/// Een badge gekoppeld aan de huidige status (wel/niet behaald, en sinds wanneer).
/// `nonisolated`: puur data, geconstrueerd binnen GameStatsStore's Task.detached.
nonisolated struct BadgeStatus: Identifiable {
    let definition: BadgeDefinition
    let unlockedDate: Date?

    var id: String { definition.id }
    var isUnlocked: Bool { unlockedDate != nil }
}
