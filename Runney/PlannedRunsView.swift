import SwiftUI

/// Toont geplande runs als een doorbladerbare week-agenda: elke dag van de week met zijn
/// naam erboven, plus/deel-knoppen samen in de navigatiebalk (i.p.v. de knop los, en het
/// grote eigen kop-blok dat voorheen hier stond) zodat de week-inhoud zelf hoger op het
/// scherm begint.
struct PlannedRunsView: View {
    @ObservedObject private var store = PlannedRunStore.shared
    @ObservedObject private var healthKit = HealthKitManager.shared
    @State private var weekOffset = 0
    @State private var showsAddForm = false
    @State private var newRunInitialDate = Date()
    @State private var selectedPlannedRun: PlannedRun?

    private let calendar = Calendar.current

    /// Begin van de zichtbare week — respecteert automatisch de locale-instelling van de
    /// eerste weekdag (maandag in NL, zondag in bijv. de VS) via dateInterval(of: .weekOfYear:).
    private var weekStart: Date {
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return calendar.date(byAdding: .weekOfYear, value: weekOffset, to: currentWeekStart) ?? currentWeekStart
    }

    private var weekDates: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var weekRangeLabel: String {
        guard let first = weekDates.first, let last = weekDates.last else { return "" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return "\(formatter.string(from: first)) – \(formatter.string(from: last))"
    }

    /// Voor het delen: altijd alle nog te lopen geplande runs, los van welke week nu op het
    /// scherm staat — anders zou je bij het delen alleen de zichtbare week meesturen.
    private var allUpcomingPlannedRuns: [PlannedRun] {
        let startOfToday = calendar.startOfDay(for: Date())
        return store.plannedRuns.filter { $0.date >= startOfToday }
    }

    private var shareURL: URL? {
        PlannedRunSharing.shareURL(for: allUpcomingPlannedRuns)
    }

    private var shareIntroText: String {
        PlannedRunSharing.shareIntroText(for: allUpcomingPlannedRuns)
    }

    private func comparison(for date: Date) -> PlannedRunComparison? {
        store.plannedRun(for: date, calendar: calendar)?.comparison(against: healthKit.lifetimeRuns, calendar: calendar)
    }

    /// Alleen de dagen van deze week die daadwerkelijk een geplande run hebben — lege dagen
    /// worden niet meer getoond (voorheen wel, als tik-om-toe-te-voegen-rij).
    private var scheduledDatesThisWeek: [Date] {
        weekDates.filter { comparison(for: $0) != nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    weekNavigationHeader

                    if store.plannedRuns.isEmpty {
                        emptyState
                    } else if scheduledDatesThisWeek.isEmpty {
                        weekEmptyState
                    } else {
                        VStack(spacing: 14) {
                            ForEach(scheduledDatesThisWeek, id: \.self) { date in
                                dayRow(for: date)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .cozyBackground()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showsAddForm) {
                PlannedRunFormView(initialDate: newRunInitialDate)
            }
            .sheet(item: $selectedPlannedRun) { plannedRun in
                PlannedRunDetailView(
                    comparison: plannedRun.comparison(against: healthKit.lifetimeRuns)
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .foregroundStyle(CozyPalette.textPrimary)
                .font(.system(size: 18, weight: .semibold))
            Text("Plan")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(CozyPalette.textPrimary)
            Spacer()
            if let shareURL {
                ShareLink(item: shareURL, message: Text(shareIntroText)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CozyPalette.textPrimary)
                }
            }
            Button {
                newRunInitialDate = Date()
                showsAddForm = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(CozyPalette.textPrimary)
            }
        }
    }

    private var weekNavigationHeader: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { weekOffset -= 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CozyPalette.textSecondary)
            }

            Spacer()

            VStack(spacing: 1) {
                Text(weekOffset == 0 ? String(localized: "This Week", comment: "Plan week navigation") : weekRangeLabel)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(CozyPalette.textPrimary)
                if weekOffset == 0 {
                    Text(weekRangeLabel)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(CozyPalette.textSecondary)
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { weekOffset = 0 }
                    } label: {
                        Text("Back to this week")
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(CozyPalette.stamina)
                    }
                }
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { weekOffset += 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CozyPalette.textSecondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(CozyPalette.cardBackground)
        .clipShape(Capsule())
    }

    private func dayRow(for date: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dayLabel(for: date))
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(calendar.isDateInToday(date) ? CozyPalette.stamina : CozyPalette.textSecondary)
                .padding(.horizontal, 4)

            if let comparison = comparison(for: date) {
                PlannedRunRow(comparison: comparison, daysUntil: daysUntil(date))
                    .contentShape(Rectangle())
                    .onTapGesture { selectedPlannedRun = comparison.plannedRun }
            }
        }
    }

    /// Aantal dagen tot de meegegeven datum, gebruikt voor de "nog X dagen"-tekst bij
    /// aankomende geplande runs (zie PlannedRunRow.secondaryText).
    private func daysUntil(_ date: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// Volledige, locale-bewuste dagnaam + datum, bv. "maandag 16 mrt" — geeft meteen de
    /// context die je nodig hebt om door een week te bladeren zonder los een kalender te
    /// hoeven raadplegen. "Vandaag" erachter zodra het om vandaag gaat.
    private func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMM")
        let label = formatter.string(from: date).capitalized
        guard calendar.isDateInToday(date) else { return label }
        return "\(label) · \(String(localized: "Today", comment: "Tab label"))"
    }

    /// Getoond als je wél al ergens geplande runs hebt, maar niet in de zichtbare week —
    /// anders zou een lege week aanvoelen als een bug i.p.v. gewoon "hier niets gepland".
    private var weekEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 26))
                .foregroundStyle(CozyPalette.textSecondary)
            Text("No planned runs this week")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Mascot(pose: .walking, height: 60)
                .padding(.bottom, 4)
            Text("No planned runs yet")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textPrimary)
            Text("Add a run from your own training schedule using the + button above.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

/// Eén rij voor een dag die wél een geplande run heeft — de datum staat al in de daglabel
/// erboven (zie dayRow), dus hier alleen nog afstand/tempo/status.
private struct PlannedRunRow: View {
    let comparison: PlannedRunComparison
    /// Alleen gebruikt voor de "nog X dagen"-tekst bij aankomende runs, zie secondaryText.
    let daysUntil: Int
    @AppStorage(distanceUnitStorageKey) private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    private var plannedRun: PlannedRun { comparison.plannedRun }

    private var statusInfo: (icon: String, color: Color) {
        switch comparison.status {
        case .upcoming: return ("circle.dashed", CozyPalette.textSecondary)
        case .missed: return ("xmark.circle.fill", CozyPalette.textSecondary)
        case .onTarget: return ("checkmark.circle.fill", CozyPalette.stamina)
        case .offTarget: return ("exclamationmark.circle.fill", CozyPalette.speed)
        }
    }

    /// Secundaire regel rechts: tempo voor een aankomende/geslaagde run, of "over hoeveel
    /// dagen" als extra duwtje richting de dag zelf.
    private var secondaryText: String {
        if comparison.status == .upcoming && daysUntil > 0 {
            return daysUntil == 1
                ? String(localized: "1 day away", comment: "Planned run countdown")
                : String(format: String(localized: "%d days away", comment: "Planned run countdown"), daysUntil)
        }
        if let max = plannedRun.targetPaceMaxSecPerKm {
            return "\(distanceUnit.formatPace(secPerKm: plannedRun.targetPaceSecPerKm))–\(distanceUnit.formatPace(secPerKm: max))"
        }
        return distanceUnit.formatPace(secPerKm: plannedRun.targetPaceSecPerKm)
    }

    private var secondaryColor: Color {
        comparison.status == .offTarget ? CozyPalette.speed : CozyPalette.textSecondary
    }

    /// 3 stipjes die de zelf-ingeschatte zwaarte tonen (zie RunIntensity) — anders dan de
    /// vorige "hoe dichtbij"-versie is dit nu altijd relevant, ook voor afgelopen runs.
    private var intensityDots: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index < plannedRun.intensity.dotCount ? plannedRun.intensity.color : CozyPalette.textSecondary.opacity(0.2))
                    .frame(width: 6, height: 6)
            }
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Image(systemName: "figure.run")
                    .foregroundStyle(CozyPalette.stamina)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 40, height: 40)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(plannedRun.label)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(CozyPalette.textPrimary)
                intensityDots
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(distanceUnit.format(km: plannedRun.distanceKm, decimals: 1))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(CozyPalette.textPrimary)
                Text(secondaryText)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(secondaryColor)
            }

            ZStack {
                Circle()
                    .stroke(CozyPalette.textSecondary.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 26, height: 26)
                Image(systemName: statusInfo.icon)
                    .foregroundStyle(statusInfo.color)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(CozyPalette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
struct PlannedRunDetailView: View {
    let comparison: PlannedRunComparison
    @AppStorage(distanceUnitStorageKey) private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var showsEditForm = false

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    private var plannedRun: PlannedRun { comparison.plannedRun }

    private var statusText: String {
        switch comparison.status {
        case .upcoming: return String(localized: "Not run yet", comment: "Planned run status")
        case .missed: return String(localized: "Missed — no matching run found", comment: "Planned run status")
        case .onTarget: return String(localized: "Right on target!", comment: "Planned run status")
        case .offTarget: return String(localized: "Off target", comment: "Planned run status")
        }
    }

    private var statusColor: Color {
        switch comparison.status {
        case .upcoming, .missed: return CozyPalette.textSecondary
        case .onTarget: return CozyPalette.stamina
        case .offTarget: return CozyPalette.speed
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    planCard
                    if let matchedRun = comparison.matchedRun {
                        comparisonCard(matchedRun: matchedRun)
                    }
                    if let notes = plannedRun.notes, !notes.isEmpty {
                        notesCard(notes)
                    }
                }
                .padding(20)
            }
            .cozyBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") { showsEditForm = true }
                }
            }
            .sheet(isPresented: $showsEditForm) {
                PlannedRunFormView(editing: plannedRun)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(plannedRun.date.formatted(date: .complete, time: .omitted))
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textSecondary)
            Text(plannedRun.label)
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(CozyPalette.textPrimary)
            Text(statusText)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(statusColor)
        }
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("The plan")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(CozyPalette.textPrimary)
            row(label: String(localized: "Distance", comment: "Badge category"), value: distanceUnit.format(km: plannedRun.distanceKm, decimals: 1))
            row(label: String(localized: "Pace", comment: "Run stat label"), value: paceRangeText)
        }
        .cozyCard()
    }

    private var paceRangeText: String {
        if let max = plannedRun.targetPaceMaxSecPerKm {
            return "\(distanceUnit.formatPace(secPerKm: plannedRun.targetPaceSecPerKm)) – \(distanceUnit.formatPace(secPerKm: max))"
        }
        return distanceUnit.formatPace(secPerKm: plannedRun.targetPaceSecPerKm)
    }

    private func comparisonCard(matchedRun: RunWorkout) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What you actually ran")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(CozyPalette.textPrimary)
            row(label: String(localized: "Distance", comment: "Badge category"), value: distanceUnit.format(km: matchedRun.distanceKm, decimals: 2), delta: distanceDeltaText)
            row(label: String(localized: "Pace", comment: "Run stat label"), value: distanceUnit.formatPace(secPerKm: matchedRun.averagePaceSecPerKm), delta: paceDeltaText)
        }
        .cozyCard()
    }

    private var distanceDeltaText: String? {
        guard let delta = comparison.distanceDeltaKm else { return nil }
        let magnitude = distanceUnit.format(km: abs(delta), decimals: 2)
        return delta >= 0 ? "+\(magnitude)" : "-\(magnitude)"
    }

    /// Tempo-delta puur als tekst, niet via distanceUnit.formatPace (die verwacht een
    /// absoluut tempo, geen verschil) — vandaar een eigen, simpele +/- sec-weergave.
    private var paceDeltaText: String? {
        guard let delta = comparison.paceDeltaSecPerKm else { return nil }
        if abs(delta) < 1 { return String(localized: "spot on", comment: "Pace delta, exactly on target") }
        let seconds = Int(abs(delta).rounded())
        return delta > 0
            ? String(format: String(localized: "%d sec slower", comment: "Pace delta"), seconds)
            : String(format: String(localized: "%d sec faster", comment: "Pace delta"), seconds)
    }

    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(CozyPalette.textPrimary)
            Text(notes)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)
        }
        .cozyCard()
    }

    private func row(label: String, value: String, delta: String? = nil) -> some View {
        HStack {
            Text(label)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(CozyPalette.textPrimary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(CozyPalette.textPrimary)
                if let delta {
                    Text(delta)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(CozyPalette.textSecondary)
                }
            }
        }
    }
}

#Preview {
    PlannedRunsView()
}
