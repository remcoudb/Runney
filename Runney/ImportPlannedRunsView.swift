import SwiftUI

/// Verschijnt zodra een `runney://`-deellink geopend is (zie RunneyApp.onOpenURL). Toont wat
/// er binnenkomt vóórdat er iets wordt opgeslagen — expliciete bevestiging i.p.v. stilzwijgend
/// importeren, want dit overschrijft mogelijk bestaande geplande runs (zie newCount/updateCount).
struct ImportPlannedRunsView: View {
    let incomingPlannedRuns: [PlannedRun]
    @ObservedObject private var store = PlannedRunStore.shared
    @AppStorage(distanceUnitStorageKey) private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue
    @Environment(\.dismiss) private var dismiss

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    private var newCount: Int {
        incomingPlannedRuns.filter { !store.exists($0.id) }.count
    }

    private var updateCount: Int {
        incomingPlannedRuns.count - newCount
    }

    private var summaryText: String {
        if updateCount == 0 {
            return String(format: String(localized: "Add %d planned runs to your schedule.", comment: "Import summary, only new runs"), newCount)
        }
        if newCount == 0 {
            return String(format: String(localized: "Update %d planned runs already in your schedule.", comment: "Import summary, only updates"), updateCount)
        }
        return String(format: String(localized: "Add %d new planned runs and update %d already in your schedule.", comment: "Import summary, mix of new and updates"), newCount, updateCount)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    VStack(spacing: 12) {
                        ForEach(incomingPlannedRuns) { plannedRun in
                            row(for: plannedRun)
                        }
                    }
                }
                .padding(20)
            }
            .cozyBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { importAll() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(CozyPalette.consistency.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: "square.and.arrow.down.on.square.fill")
                        .foregroundStyle(CozyPalette.consistency)
                        .font(.system(size: 18, weight: .semibold))
                }
                Text("Import Planned Runs")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(CozyPalette.textPrimary)
            }
            Text(summaryText)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)
        }
    }

    private func row(for plannedRun: PlannedRun) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(CozyPalette.consistency.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "figure.run")
                    .foregroundStyle(CozyPalette.consistency)
                    .font(.system(size: 15, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(plannedRun.label)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(CozyPalette.textPrimary)
                Text("\(plannedRun.date.formatted(date: .abbreviated, time: .omitted)) · \(distanceUnit.format(km: plannedRun.distanceKm, decimals: 1)) · \(distanceUnit.formatPace(secPerKm: plannedRun.targetPaceSecPerKm))")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(CozyPalette.textSecondary)
            }

            Spacer()

            if store.exists(plannedRun.id) {
                Text("Update")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(CozyPalette.speed)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(CozyPalette.speed.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .cozyCard()
    }

    private func importAll() {
        for plannedRun in incomingPlannedRuns {
            store.upsert(plannedRun)
        }
        dismiss()
    }
}

#Preview {
    ImportPlannedRunsView(incomingPlannedRuns: [
        PlannedRun(date: Date(), distanceKm: 5, targetPaceSecPerKm: 330, label: "Tempo run")
    ])
}
