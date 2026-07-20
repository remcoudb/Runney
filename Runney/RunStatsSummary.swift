import Foundation

/// Algemene, beschrijvende hardloopstatistieken — geen spelscore, puur "wat heb je gelopen".
/// Bewust op kalenderweek/kalenderjaar gebaseerd (niet de rollende vensters die GameEngine
/// gebruikt voor de spelscores) omdat dat intuïtiever aanvoelt voor kale cijfers.
/// `nonisolated`: pure berekening zonder gedeelde state, aangeroepen vanuit GameStatsStore's
/// Task.detached (zie GameEngine voor dezelfde reden).
nonisolated struct RunStatsSummary {
    let weekKm: Double
    let yearKm: Double
    let bestMonth: (label: String, km: Double)?
    let longestRun: RunWorkout?
    let fastestRun: RunWorkout?

    static func calculate(from runs: [RunWorkout], now: Date = Date(), calendar: Calendar = .current) -> RunStatsSummary {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let weekKm = runs
            .filter { $0.startDate >= weekStart && $0.startDate <= now }
            .reduce(0) { $0 + $1.distanceKm }

        let yearStart = calendar.dateInterval(of: .year, for: now)?.start ?? now
        let yearKm = runs
            .filter { $0.startDate >= yearStart && $0.startDate <= now }
            .reduce(0) { $0 + $1.distanceKm }

        let monthlyTotals = Dictionary(grouping: runs) { run in
            calendar.dateComponents([.year, .month], from: run.startDate)
        }.mapValues { runsInMonth in
            runsInMonth.reduce(0.0) { $0 + $1.distanceKm }
        }

        let bestMonth: (label: String, km: Double)?
        if let entry = monthlyTotals.max(by: { $0.value < $1.value }),
           let date = calendar.date(from: entry.key) {
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
            bestMonth = (formatter.string(from: date).capitalized, entry.value)
        } else {
            bestMonth = nil
        }

        let longestRun = runs.max { $0.distanceKm < $1.distanceKm }
        // Alleen runs van 1+ km meenemen voor "snelste", anders kan een heel kort ruizig
        // stukje met een toevallig extreem tempo de titel "winnen".
        let fastestRun = runs
            .filter { $0.distanceKm >= 1 }
            .min { $0.averagePaceSecPerKm < $1.averagePaceSecPerKm }

        return RunStatsSummary(
            weekKm: weekKm,
            yearKm: yearKm,
            bestMonth: bestMonth,
            longestRun: longestRun,
            fastestRun: fastestRun
        )
    }
}
