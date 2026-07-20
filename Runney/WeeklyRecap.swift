import Foundation

/// Vergelijkbaar met TodaySummary, maar dan voor de hele (kalender)week: wat heeft deze week
/// tot nu toe opgeleverd t.o.v. de stand bij het begin van de week.
/// `nonisolated`: puur data, geconstrueerd binnen GameStatsStore's Task.detached.
nonisolated struct WeeklyRecap {
    let weekStart: Date
    let hasRunThisWeek: Bool
    let weekRuns: [RunWorkout]
    let totalDistanceKm: Double

    let levelAtWeekStart: Int
    let levelNow: Int
    let staminaDelta: Int
    let consistencyDelta: Int
    let speedDelta: Int
    let xpGained: Int

    /// Eén entry per dag van de week (maandag t/m zondag), voor de weekstrip-visualisatie
    /// op de "Deze week"-kaart — heeft de gebruiker die dag gelopen, en is het vandaag?
    let dayStatuses: [WeekDayStatus]

    var runCount: Int { weekRuns.count }
    var didLevelUp: Bool { levelNow > levelAtWeekStart }
}

/// Eén dag binnen de weekstrip. `nonisolated`: zelfde reden als WeeklyRecap.
nonisolated struct WeekDayStatus: Identifiable {
    let id: Int
    /// Korte, locale-bewuste dagnaam (bv. "Ma", "Di") — via Calendar/DateFormatter i.p.v.
    /// hardcoded Nederlandse letters, zodat dit vanzelf meebeweegt als de app ooit meertalig wordt.
    let label: String
    let hasRun: Bool
    let isToday: Bool
}

/// `nonisolated`: zie GameEngineTrend.swift voor waarom dit expliciet herhaald moet worden.
nonisolated extension GameEngine {
    /// Vergelijkt de score van nu met de score zoals die was bij het begin van de kalenderweek
    /// — dus zonder de runs van deze week. Zelfde truc als todaySummary: `calculate` gewoon
    /// met een teruggeschoven `now` aanroepen, werkt correct dankzij de bovengrens-filters
    /// (zie GameEngine.calculate). Bewust een kalenderweek, niet het rollende venster van de
    /// live scores — intuïtiever voor "deze week", zelfde conventie als RunStatsSummary en
    /// GoalType.weeklyDistance.
    static func weeklyRecap(from runs: [RunWorkout], now: Date = Date(), calendar: Calendar = .current) -> WeeklyRecap {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let weekRuns = runs
            .filter { $0.startDate >= weekStart && $0.startDate < now }
            .sorted { $0.startDate < $1.startDate }

        let statsNow = calculate(from: runs, now: now, calendar: calendar)
        let statsAtWeekStart = calculate(from: runs, now: weekStart, calendar: calendar)

        let dayStatuses: [WeekDayStatus] = (0..<7).compactMap { offset -> WeekDayStatus? in
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let hasRun = weekRuns.contains { calendar.isDate($0.startDate, inSameDayAs: dayDate) }
            let isToday = calendar.isDate(dayDate, inSameDayAs: now)
            let rawLabel = dayDate.formatted(.dateTime.weekday(.abbreviated))
            let label = rawLabel.prefix(1).uppercased() + rawLabel.dropFirst()
            return WeekDayStatus(id: offset, label: label, hasRun: hasRun, isToday: isToday)
        }

        return WeeklyRecap(
            weekStart: weekStart,
            hasRunThisWeek: !weekRuns.isEmpty,
            weekRuns: weekRuns,
            totalDistanceKm: weekRuns.reduce(0) { $0 + $1.distanceKm },
            levelAtWeekStart: statsAtWeekStart.level,
            levelNow: statsNow.level,
            staminaDelta: statsNow.stamina - statsAtWeekStart.stamina,
            consistencyDelta: statsNow.consistency - statsAtWeekStart.consistency,
            speedDelta: statsNow.speed - statsAtWeekStart.speed,
            xpGained: statsNow.totalXP - statsAtWeekStart.totalXP,
            dayStatuses: dayStatuses
        )
    }
}
