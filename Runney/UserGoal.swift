import Foundation
import SwiftUI

/// De soorten persoonlijke doelen die een gebruiker kan instellen. Los van de automatische
/// GameEngine-scores — dit is puur een zelfgekozen doel dat de gebruiker motiveert.
enum GoalType: String, CaseIterable, Identifiable {
    case weeklyDistance
    case monthlyDistance
    case weeklyFrequency

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weeklyDistance: return String(localized: "Distance per week", comment: "Goal type option")
        case .monthlyDistance: return String(localized: "Distance per month", comment: "Goal type option")
        case .weeklyFrequency: return String(localized: "Times per week", comment: "Goal type option")
        }
    }

    /// Doel-waarden zijn altijd intern in km opgeslagen voor de afstandsdoelen — zie
    /// DistanceUnit voor waar de omrekening naar de gekozen weergave-eenheid gebeurt.
    var defaultTarget: Double {
        switch self {
        case .weeklyDistance: return 20
        case .monthlyDistance: return 80
        case .weeklyFrequency: return 3
        }
    }

    /// Ook deze grenzen zijn in km — GoalPickerFields rekent ze om naar de weergave-eenheid.
    var stepperRange: ClosedRange<Double> {
        switch self {
        case .weeklyDistance: return 1...100
        case .monthlyDistance: return 5...400
        case .weeklyFrequency: return 1...14
        }
    }

    private var isDistanceBased: Bool {
        self == .weeklyDistance || self == .monthlyDistance
    }

    /// Eenheid-label voor weergave, bv. "km"/"mi" voor afstandsdoelen of "x" voor een
    /// frequentiedoel.
    func displayUnit(using distanceUnit: DistanceUnit) -> String {
        isDistanceBased ? distanceUnit.abbreviation : String(localized: "x", comment: "Suffix for a count-based goal, e.g. '3x per week'")
    }

    /// Bewust op kalenderweek/kalendermaand gebaseerd — zelfde conventie als de Loopstats-tab,
    /// intuïtiever voor een zelfgekozen doel dan de rollende vensters van de GameEngine-scores.
    func progress(from runs: [RunWorkout], target: Double, now: Date = Date(), calendar: Calendar = .current) -> GoalProgress {
        switch self {
        case .weeklyDistance:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            let km = runs.filter { $0.startDate >= start && $0.startDate <= now }.reduce(0) { $0 + $1.distanceKm }
            return GoalProgress(current: km, target: target, periodLabel: String(localized: "this week", comment: "Goal progress period label"))

        case .monthlyDistance:
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
            let km = runs.filter { $0.startDate >= start && $0.startDate <= now }.reduce(0) { $0 + $1.distanceKm }
            return GoalProgress(current: km, target: target, periodLabel: String(localized: "this month", comment: "Goal progress period label"))

        case .weeklyFrequency:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            let count = runs.filter { $0.startDate >= start && $0.startDate <= now }.count
            return GoalProgress(current: Double(count), target: target, periodLabel: String(localized: "this week", comment: "Goal progress period label"))
        }
    }
}

/// Het resultaat van het doorrekenen van een GoalType tegen de huidige runs. `current`/`target`
/// staan voor afstandsdoelen altijd in km — GoalCard (Home) en GoalPickerFields rekenen zelf
/// om naar de gekozen weergave-eenheid.
struct GoalProgress {
    let current: Double
    let target: Double
    let periodLabel: String

    var fraction: Double {
        guard target > 0 else { return 0 }
        return min(current / target, 1)
    }

    var percentText: String {
        "\(Int((fraction * 100).rounded()))%"
    }
}

// MARK: - Gedeeld invoerstuk (Profiel + onboarding)

/// De picker + stepper om een doel in te stellen — los van een kaart-omhulsel, zodat zowel
/// ProfileView als de onboarding-flow 'm in hun eigen context kunnen plaatsen.
struct GoalPickerFields: View {
    @Binding var goalTypeRaw: String
    /// Altijd in km opgeslagen voor afstandsdoelen — zie DistanceUnit voor de omrekening.
    @Binding var goalTarget: Double
    @AppStorage(distanceUnitStorageKey) private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    private var goalType: GoalType {
        GoalType(rawValue: goalTypeRaw) ?? .weeklyDistance
    }

    private var isDistanceBased: Bool {
        goalType == .weeklyDistance || goalType == .monthlyDistance
    }

    /// Presenteert/wijzigt het opgeslagen km-doel in de door de gebruiker gekozen eenheid —
    /// de stepper zelf weet niets van km/miles, die ziet alleen de weergavewaarde.
    private var displayTargetBinding: Binding<Double> {
        Binding(
            get: { isDistanceBased ? distanceUnit.convert(fromKm: goalTarget) : goalTarget },
            set: { newValue in
                goalTarget = isDistanceBased ? distanceUnit.convertToKm(newValue) : newValue
            }
        )
    }

    private var displayStepperRange: ClosedRange<Double> {
        guard isDistanceBased else { return goalType.stepperRange }
        let lower = distanceUnit.convert(fromKm: goalType.stepperRange.lowerBound)
        let upper = distanceUnit.convert(fromKm: goalType.stepperRange.upperBound)
        return lower...upper
    }

    private var formattedTarget: String {
        isDistanceBased ? String(format: "%.0f", displayTargetBinding.wrappedValue) : "\(Int(goalTarget))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $goalTypeRaw) {
                ForEach(GoalType.allCases) { type in
                    Text(type.title).tag(type.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: goalTypeRaw) { _, newValue in
                if let type = GoalType(rawValue: newValue) {
                    goalTarget = type.defaultTarget
                }
            }

            HStack {
                Text("\(String(localized: "Goal", comment: "Label before a goal value, e.g. 'Goal: 20 km'")): \(formattedTarget) \(goalType.displayUnit(using: distanceUnit))")
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(CozyPalette.textPrimary)
                Spacer()
                Stepper("", value: displayTargetBinding, in: displayStepperRange, step: 1)
                    .labelsHidden()
            }
        }
    }
}
