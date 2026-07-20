import SwiftUI

struct PersonalRecordsView: View {
    let records: PersonalRecords
    @AppStorage(distanceUnitStorageKey) private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard

                    if records.records.isEmpty {
                        emptyState
                    } else {
                        ForEach(records.records) { record in
                            RecordRow(record: record, distanceUnit: distanceUnit)
                        }
                    }
                }
                .padding(20)
            }
            .cozyBackground()
            .navigationTitle("Personal Records")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: RunWorkout.self) { run in
                RunDetailView(run: run)
            }
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 0) {
            statBlock(value: distanceUnit.format(km: records.totalLifetimeKm, decimals: 0), label: String(localized: "All-time total", comment: "Personal records summary"))
            statBlock(value: "\(records.totalLifetimeRuns)", label: String(localized: "All-time runs", comment: "Personal records summary"))
        }
        .cozyCard()
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(CozyPalette.textPrimary)
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "trophy")
                .font(.system(size: 32))
                .foregroundStyle(CozyPalette.textSecondary)
            Text("No records yet")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textPrimary)
            Text("Once you've logged a few runs, your personal records will show up here.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

private struct RecordRow: View {
    let record: PersonalRecord
    let distanceUnit: DistanceUnit

    var body: some View {
        if let run = record.run {
            NavigationLink(value: run) {
                rowContent(showsChevron: true)
            }
            .buttonStyle(.plain)
        } else {
            rowContent(showsChevron: false)
        }
    }

    private func rowContent(showsChevron: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(CozyPalette.speed.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: record.icon)
                    .foregroundStyle(CozyPalette.speed)
                    .font(.system(size: 17, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(record.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(CozyPalette.textPrimary)
                Text(record.detailText(using: distanceUnit))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(CozyPalette.textSecondary)
            }

            Spacer(minLength: 8)

            Text(record.valueText(using: distanceUnit))
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(CozyPalette.textPrimary)
                .multilineTextAlignment(.trailing)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CozyPalette.textSecondary)
            }
        }
        .cozyCard()
    }
}

#Preview {
    PersonalRecordsView(records: .calculate(from: []))
}
