import SwiftUI
import Charts

/// Compacte kaart voor racegereedheid — regelt zijn eigen detail-sheet, zodat zowel Home
/// als Stats 'm zonder extra state kunnen neerzetten.
/// Compacte, banner-achtige weergave voor Home — regelt net als RaceReadinessCard zijn eigen
/// detail-sheet, dus zonder extra state in de aanroepende view. RaceReadinessCard zelf (met
/// eigen voortgangsbalk en statustekst) blijft de volledige kaart-versie voor Stats.
struct RaceReadinessCompactBanner: View {
    let readiness: RaceReadiness
    let runs: [RunWorkout]
    @State private var showsDetail = false

    var body: some View {
        Button {
            showsDetail = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CozyPalette.speed)
                Text(readiness.goal.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(CozyPalette.textPrimary)
                Spacer()
                Text("\(readiness.totalScore)/100")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(CozyPalette.speed)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CozyPalette.textSecondary)
            }
            .cozyCard()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showsDetail) {
            RaceReadinessDetailSheet(readiness: readiness, runs: runs)
        }
    }
}

struct RaceReadinessCard: View {
    let readiness: RaceReadiness
    /// Nodig om de trendgrafiek hieronder te kunnen berekenen — de kaart zelf regelt dit,
    /// zodat StatsView 'm net als voorheen zonder extra state kan neerzetten.
    let runs: [RunWorkout]
    @State private var showsDetail = false

    private var trend: [RaceReadinessTrendPoint] {
        GameEngine.raceReadinessTrend(goal: readiness.goal, runs: runs)
    }

    var body: some View {
        Button {
            showsDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(readiness.goal.title)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(CozyPalette.textPrimary)
                        Text(weeksRemainingLabel)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(CozyPalette.textSecondary)
                    }
                    Spacer()
                    Text("\(readiness.totalScore)/100")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(CozyPalette.speed)
                }

                // Zelfde grafiekstijl als de Stamina/Consistentie/Snelheid-kaarten hierboven —
                // dat was precies waar dit kaartje eerder in afweek: een kale voortgangsbalk
                // i.p.v. de opbouw over tijd te laten zien.
                Chart(trend) { point in
                    AreaMark(
                        x: .value("Week", point.date),
                        y: .value("Score", point.score)
                    )
                    .foregroundStyle(CozyPalette.speed.opacity(0.12))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Week", point.date),
                        y: .value("Score", point.score)
                    )
                    .foregroundStyle(CozyPalette.speed)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 56)

                Text(readiness.statusMessage)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(CozyPalette.textSecondary)
            }
            .cozyCard()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showsDetail) {
            RaceReadinessDetailSheet(readiness: readiness, runs: runs)
        }
    }

    private var weeksRemainingLabel: String {
        if readiness.hasRacePassed {
            let weeksAgo = -readiness.weeksRemaining
            return weeksAgo == 1
                ? String(localized: "Was 1 week ago", comment: "Race readiness countdown, race already happened")
                : String(format: String(localized: "Was %d weeks ago", comment: "Race readiness countdown, race already happened"), weeksAgo)
        }
        if readiness.weeksRemaining == 0 { return String(localized: "This week!", comment: "Race readiness countdown") }
        return readiness.weeksRemaining == 1
            ? String(localized: "1 week to go", comment: "Race readiness countdown")
            : String(format: String(localized: "%d weeks to go", comment: "Race readiness countdown"), readiness.weeksRemaining)
    }
}

/// Detailscherm met de drie factoren uitgesplitst — zelfde visuele taal als StatDetailSheet,
/// maar als los component omdat de vorm (drie genoemde factoren + wedstrijdgegevens i.p.v.
/// "Deze week"-rijen + tips) genoeg afwijkt om niet in StatDetailContent te persen.
struct RaceReadinessDetailSheet: View {
    let readiness: RaceReadiness
    let runs: [RunWorkout]
    @Environment(\.dismiss) private var dismiss
    @AppStorage(distanceUnitStorageKey) private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    private var trend: [RaceReadinessTrendPoint] {
        GameEngine.raceReadinessTrend(goal: readiness.goal, runs: runs)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                Text(readiness.statusMessage)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(CozyPalette.textPrimary)

                trendChart

                sectionTitle("How the score is built")
                VStack(spacing: 16) {
                    factorRow(
                        label: String(format: String(localized: "Longest training run (last %d weeks)", comment: "Race readiness factor label"), GameConstants.raceReadinessLookbackWeeks),
                        detail: longestRunDetail,
                        score: readiness.longestRunScore, max: Int(GameConstants.raceReadinessLongestRunWeight)
                    )
                    factorRow(
                        label: String(format: String(localized: "Weekly volume (last %d weeks)", comment: "Race readiness factor label"), GameConstants.raceReadinessLookbackWeeks),
                        detail: String(format: String(localized: "%@ of %d %@ target", comment: "e.g. '32.1 km of 36 km target'"), kmString(readiness.weeklyVolumeKm), Int(distanceUnit.convert(fromKm: readiness.weeklyVolumeTargetKm).rounded()), distanceUnit.abbreviation),
                        score: readiness.weeklyVolumeScore, max: Int(GameConstants.raceReadinessWeeklyVolumeWeight)
                    )
                    factorRow(
                        label: String(localized: "Consistency", comment: "Substat name"),
                        detail: String(format: String(localized: "Consistency score: %d/100", comment: "Race readiness factor detail"), readiness.consistencyScore),
                        score: readiness.consistencyContribution, max: Int(GameConstants.raceReadinessConsistencyWeight)
                    )
                }
                .padding(16)
                .background(CozyPalette.background)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                sectionTitle("Race")
                VStack(spacing: 0) {
                    detailRow(label: String(localized: "Distance", comment: "Badge category"), value: distanceUnit.format(km: readiness.goal.distanceKm, decimals: 1))
                    Divider().opacity(0.5)
                    detailRow(label: String(localized: "Date", comment: "Race detail label"), value: readiness.goal.raceDate.formatted(date: .abbreviated, time: .omitted))
                }
                .padding(.horizontal, 16)
                .background(CozyPalette.background)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                doneButton
            }
            .padding(20)
        }
        .background(CozyPalette.cardBackground.ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 10) {
                Image(systemName: "flag.checkered")
                    .foregroundStyle(CozyPalette.speed)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 28, height: 28)
                Text(readiness.goal.title)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(CozyPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
            Text("\(readiness.totalScore)/100")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(CozyPalette.speed)
        }
    }

    private var trendChart: some View {
        Chart(trend) { point in
            AreaMark(
                x: .value("Week", point.date),
                y: .value("Score", point.score)
            )
            .foregroundStyle(CozyPalette.speed.opacity(0.12))
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("Week", point.date),
                y: .value("Score", point.score)
            )
            .foregroundStyle(CozyPalette.speed)
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 2.5))
        }
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 90)
    }

    /// Toont expliciet "X weken geleden" zodat direct duidelijk is waarom de score lager kan
    /// zijn dan de kale km-verhouding zou suggereren (recency-weging, zie RaceReadiness.swift).
    private var longestRunDetail: String {
        guard readiness.longestRunKm > 0 else {
            return String(format: String(localized: "No training run yet in the last %d weeks · target: %d km", comment: "Race readiness longest run detail, empty state"), GameConstants.raceReadinessLookbackWeeks, Int(readiness.longestRunTargetKm))
        }
        let weeksAgoText = readiness.longestRunWeeksAgo == 0
            ? String(localized: "this week", comment: "Race readiness longest run timing")
            : (readiness.longestRunWeeksAgo == 1
                ? String(localized: "1 week ago", comment: "Race readiness longest run timing")
                : String(format: String(localized: "%d weeks ago", comment: "Race readiness longest run timing"), readiness.longestRunWeeksAgo))
        return String(format: String(localized: "%@, %@ · target: %d %@", comment: "e.g. '16.0 km, 2 weeks ago · target: 17 km'"), kmString(readiness.longestRunKm), weeksAgoText, Int(distanceUnit.convert(fromKm: readiness.longestRunTargetKm).rounded()), distanceUnit.abbreviation)
    }

    private func factorRow(label: String, detail: String, score: Int, max: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(CozyPalette.textPrimary)
                Spacer()
                Text("\(score)/\(max)")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(CozyPalette.speed)
            }
            Text(detail)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(CozyPalette.textPrimary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textSecondary)
        }
        .padding(.vertical, 10)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(CozyPalette.textPrimary)
    }

    private func kmString(_ km: Double) -> String {
        distanceUnit.format(km: km, decimals: 1)
    }

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Done")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.primaryButtonText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(CozyPalette.primaryButtonBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.top, 8)
    }
}

/// Invoerstuk om een RaceGoal in te stellen — afstand via een menu-picker (5 opties passen
/// niet fijn in een segmented control), een stepper voor een eigen afstand, en een DatePicker.
struct RaceGoalEditor: View {
    let goal: RaceGoal
    let onChange: (RaceGoal) -> Void
    @AppStorage(distanceUnitStorageKey) private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    /// Presenteert/wijzigt de opgeslagen km-afstand in de gekozen weergave-eenheid — de
    /// stepper zelf weet niets van km/miles, die ziet alleen de weergavewaarde.
    private var displayCustomKmBinding: Binding<Double> {
        Binding(
            get: { distanceUnit.convert(fromKm: goal.customKm) },
            set: { newValue in
                onChange(RaceGoal(distanceType: goal.distanceType, customKm: distanceUnit.convertToKm(newValue), raceDate: goal.raceDate))
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(String(localized: "Distance", comment: "Badge category"), selection: Binding(
                get: { goal.distanceType },
                set: { onChange(RaceGoal(distanceType: $0, customKm: goal.customKm, raceDate: goal.raceDate)) }
            )) {
                ForEach(RaceGoal.Distance.allCases) { distance in
                    Text(distance.title).tag(distance)
                }
            }
            .pickerStyle(.menu)
            .tint(CozyPalette.textPrimary)

            if goal.distanceType == .custom {
                HStack {
                    Text(String(format: String(localized: "Distance: %.1f %@", comment: "e.g. 'Distance: 15.0 km'"), displayCustomKmBinding.wrappedValue, distanceUnit.abbreviation))
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(CozyPalette.textPrimary)
                    Spacer()
                    Stepper("", value: displayCustomKmBinding, in: distanceUnit.convert(fromKm: 1)...distanceUnit.convert(fromKm: 200), step: 1)
                        .labelsHidden()
                }
            }

            DatePicker(
                String(localized: "Race date", comment: "Date picker label"),
                selection: Binding(
                    get: { goal.raceDate },
                    set: { onChange(RaceGoal(distanceType: goal.distanceType, customKm: goal.customKm, raceDate: $0)) }
                ),
                displayedComponents: .date
            )
            .font(.system(.body, design: .rounded))
            .tint(CozyPalette.textPrimary)
        }
    }
}
