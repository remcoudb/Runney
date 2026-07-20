import SwiftUI

/// Toevoegen én bewerken delen dit ene formulier — bij bewerken wordt het gewoon
/// voorgevuld met de bestaande PlannedRun, en overschrijft Opslaan 'm i.p.v. een nieuwe
/// aan te maken.
struct PlannedRunFormView: View {
    @ObservedObject private var store = PlannedRunStore.shared
    @AppStorage(distanceUnitStorageKey) private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue
    @Environment(\.dismiss) private var dismiss

    /// nil = nieuwe geplande run aanmaken, anders het id van de run die bewerkt wordt.
    private let editingID: UUID?

    @State private var date: Date
    @State private var distanceKm: Double
    @State private var targetPaceSecPerKm: Double
    @State private var hasPaceRange: Bool
    @State private var targetPaceMaxSecPerKm: Double
    @State private var label: String
    @State private var notes: String
    @State private var intensity: RunIntensity
    @State private var showsDeleteConfirmation = false

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    /// Nieuw formulier, met redelijke standaardwaarden (5 km, 6:00/km, "Duurloop").
    /// `initialDate` is standaard vandaag, maar PlannedRunsView geeft hier de datum van de
    /// aangetikte lege dag mee, zodat je 'm niet nog een keer los hoeft te kiezen.
    init(initialDate: Date = Date()) {
        self.editingID = nil
        self._date = State(initialValue: initialDate)
        self._distanceKm = State(initialValue: 5)
        self._targetPaceSecPerKm = State(initialValue: 360)
        self._hasPaceRange = State(initialValue: false)
        self._targetPaceMaxSecPerKm = State(initialValue: 390)
        self._label = State(initialValue: "")
        self._notes = State(initialValue: "")
        self._intensity = State(initialValue: .medium)
    }

    /// Bewerk-formulier, voorgevuld vanuit een bestaande PlannedRun.
    init(editing plannedRun: PlannedRun) {
        self.editingID = plannedRun.id
        self._date = State(initialValue: plannedRun.date)
        self._distanceKm = State(initialValue: plannedRun.distanceKm)
        self._targetPaceSecPerKm = State(initialValue: plannedRun.targetPaceSecPerKm)
        self._hasPaceRange = State(initialValue: plannedRun.hasPaceRange)
        self._targetPaceMaxSecPerKm = State(initialValue: plannedRun.targetPaceMaxSecPerKm ?? (plannedRun.targetPaceSecPerKm + 30))
        self._label = State(initialValue: plannedRun.label)
        self._notes = State(initialValue: plannedRun.notes ?? "")
        self._intensity = State(initialValue: plannedRun.intensity)
    }

    private var isEditing: Bool { editingID != nil }

    private var isValid: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && distanceKm > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    labelCard
                    intensityCard
                    dateCard
                    distanceCard
                    paceCard
                    notesCard
                    if isEditing {
                        deleteButton
                    }
                }
                .padding(20)
            }
            .cozyBackground()
            .navigationTitle(isEditing ? String(localized: "Edit Planned Run", comment: "Planned run form title") : String(localized: "New Planned Run", comment: "Planned run form title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog(
                "Delete this planned run?",
                isPresented: $showsDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { delete() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var labelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Type of run")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textSecondary)
            TextField("e.g. Tempo run, Long run, Recovery run", text: $label)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(CozyPalette.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(CozyPalette.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .autocorrectionDisabled()
        }
        .cozyCard()
    }

    private var intensityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Intensity")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textSecondary)

            Picker("", selection: $intensity) {
                ForEach(RunIntensity.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index < intensity.dotCount ? intensity.color : CozyPalette.textSecondary.opacity(0.2))
                        .frame(width: 8, height: 8)
                }
                Text("How this run will look in the weekly overview")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(CozyPalette.textSecondary)
                    .padding(.leading, 4)
            }
        }
        .cozyCard()
    }

    private var dateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Date")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textSecondary)
            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(CozyPalette.textPrimary)
        }
        .cozyCard()
    }

    private var distanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Distance")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textSecondary)
            HStack {
                Text(distanceUnit.format(km: distanceKm, decimals: 1))
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(CozyPalette.textPrimary)
                Spacer()
                Stepper("", value: displayDistanceBinding, in: distanceUnit.convert(fromKm: 0.5)...distanceUnit.convert(fromKm: 100), step: distanceUnit == .kilometers ? 0.5 : 0.25)
                    .labelsHidden()
            }
        }
        .cozyCard()
    }

    /// Presenteert/wijzigt de opgeslagen km-afstand in de gekozen weergave-eenheid — zelfde
    /// patroon als GoalPickerFields/RaceGoalEditor.
    private var displayDistanceBinding: Binding<Double> {
        Binding(
            get: { distanceUnit.convert(fromKm: distanceKm) },
            set: { distanceKm = distanceUnit.convertToKm($0) }
        )
    }

    private var paceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Target pace")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textSecondary)

            paceStepperRow(label: hasPaceRange ? String(localized: "From", comment: "Pace range lower bound label") : String(localized: "Pace", comment: "Single target pace label"), value: $targetPaceSecPerKm)

            Toggle(isOn: $hasPaceRange) {
                Text("Use a pace range")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(CozyPalette.textPrimary)
            }
            .tint(CozyPalette.stamina)

            if hasPaceRange {
                paceStepperRow(label: String(localized: "To", comment: "Pace range upper bound label"), value: $targetPaceMaxSecPerKm)
            }
        }
        .cozyCard()
    }

    /// Stapt in vaste sec/km-increments — de weergave schakelt wel mee met de gekozen
    /// eenheid (via distanceUnit.formatPace), maar de stapgrootte zelf blijft in km-termen.
    /// Simpeler dan de stapgrootte zelf ook omrekenen, en voor een doeltempo instellen is
    /// perfecte precisie in mile-termen niet cruciaal.
    private func paceStepperRow(label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(CozyPalette.textPrimary)
            Spacer()
            Text(distanceUnit.formatPace(secPerKm: value.wrappedValue))
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textPrimary)
            Stepper("", value: value, in: 150...900, step: 5)
                .labelsHidden()
        }
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes (optional)")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textSecondary)
            TextField("e.g. Include 4x 1km at threshold pace", text: $notes, axis: .vertical)
                .lineLimit(3...6)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(CozyPalette.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(CozyPalette.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .cozyCard()
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showsDeleteConfirmation = true
        } label: {
            Text("Delete Planned Run")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
    }

    private func save() {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let plannedRun = PlannedRun(
            id: editingID ?? UUID(),
            date: date,
            distanceKm: distanceKm,
            targetPaceSecPerKm: targetPaceSecPerKm,
            targetPaceMaxSecPerKm: hasPaceRange ? targetPaceMaxSecPerKm : nil,
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            intensity: intensity
        )
        if isEditing {
            store.update(plannedRun)
        } else {
            store.add(plannedRun)
        }
        dismiss()
    }

    private func delete() {
        guard let editingID else { return }
        store.plannedRuns.first(where: { $0.id == editingID }).map { store.delete($0) }
        dismiss()
    }
}

#Preview {
    PlannedRunFormView()
}
