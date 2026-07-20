import SwiftUI
import MapKit

struct RunDetailView: View {
    let run: RunWorkout
    @ObservedObject private var healthKit = HealthKitManager.shared
    @AppStorage(distanceUnitStorageKey) private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue

    @State private var splits: [RunSplit] = []
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var cameraPosition: MapCameraPosition = .automatic

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    private var xpEarned: Int {
        Int((run.distanceKm * GameConstants.xpPerKm).rounded())
    }

    /// Alleen runs sinds het eerste gebruik van de app tellen mee voor XP — zie GameEngine.calculateLevel.
    private var countsForXP: Bool {
        run.startDate >= AppInstallDate.value
    }

    private var durationText: String {
        let totalSeconds = Int(run.durationSeconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// De hoeveelste run van de (kalender)week dit was — puur informatief, niet 1-op-1 de
    /// rollende-week-logica die de consistentie-score gebruikt (zie StatDetailContent.consistency).
    private var weekRunNumber: Int? {
        let calendar = Calendar.current
        let sameWeek = healthKit.runs
            .filter { calendar.isDate($0.startDate, equalTo: run.startDate, toGranularity: .weekOfYear) }
            .sorted { $0.startDate < $1.startDate }
        return sameWeek.firstIndex(where: { $0.id == run.id }).map { $0 + 1 }
    }

    /// Tot wanneer de tempo/interval-bonus (Snelheid) actief blijft door deze run.
    private var bonusActiveUntil: Date? {
        guard run.effortType.isTempo || run.effortType.isInterval else { return nil }
        return Calendar.current.date(byAdding: .day, value: GameConstants.speedBonusWindowDays, to: run.startDate)
    }

    /// Locale-bewust: NumberFormatter met .ordinal geeft automatisch "2nd" in het Engels en
    /// "2e" in het Nederlands, gebaseerd op de systeemtaal — geen aparte vertaling nodig.
    private func ordinalText(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    /// Camera-gebied dat de hele route in beeld brengt, met een kleine marge.
    private var routeRegion: MKCoordinateRegion? {
        guard !routeCoordinates.isEmpty else { return nil }
        let lats = routeCoordinates.map(\.latitude)
        let lons = routeCoordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }

        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.005),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.005)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !routeCoordinates.isEmpty {
                    mapCard
                }

                header
                statsGrid

                if run.effortType.isTempo || run.effortType.isInterval {
                    effortCard
                }

                if !splits.isEmpty {
                    splitsCard
                }

                contributionCard
                xpCard
            }
            .padding(20)
        }
        .cozyBackground()
        .navigationTitle(run.startDate.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            async let fetchedSplits = healthKit.fetchKilometerSplits(for: run.id)
            async let fetchedRoute = healthKit.fetchRoute(for: run.id)
            splits = await fetchedSplits
            routeCoordinates = await fetchedRoute
            if let routeRegion {
                cameraPosition = .region(routeRegion)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(run.startDate.formatted(date: .complete, time: .omitted))
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textSecondary)
            Text(distanceUnit.format(km: run.distanceKm))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(CozyPalette.textPrimary)
            Text("Started at \(run.startDate.formatted(date: .omitted, time: .shortened))")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)
        }
    }

    private static let gridColumns = [GridItem(.flexible()), GridItem(.flexible())]

    private var statsGrid: some View {
        LazyVGrid(columns: Self.gridColumns, spacing: 12) {
            statTile(label: String(localized: "Pace", comment: "Run stat label"), value: distanceUnit.formatPace(secPerKm: run.averagePaceSecPerKm), color: CozyPalette.speed)
            statTile(label: String(localized: "Duration", comment: "Run stat label"), value: durationText, color: CozyPalette.stamina)
            if let calories = run.caloriesBurned {
                statTile(label: String(localized: "Calories", comment: "Run stat label"), value: "\(Int(calories.rounded()))", color: CozyPalette.consistency)
            }
            if let heartRate = run.averageHeartRate {
                statTile(label: String(localized: "Heart Rate", comment: "Run stat label"), value: "\(Int(heartRate.rounded())) bpm", color: CozyPalette.level)
            }
        }
        // Duration staat altijd als tweede tegel (rechtsboven) — Calorieën/Hartslag zijn
        // voorwaardelijk maar komen altijd ERONDER, dus deze positie klopt hoe dan ook,
        // ongeacht welke van de twee optionele tegels er wel/niet bij staan.
        .overlay(alignment: .topTrailing) {
            Mascot(pose: .running, height: 36)
                .offset(x: -60, y: -35)
        }
    }

    private func statTile(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .cozyCard()
    }

    private var mapCard: some View {
        Map(position: $cameraPosition) {
            MapPolyline(coordinates: routeCoordinates)
                .stroke(CozyPalette.stamina, lineWidth: 4)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .disabled(true) // puur ter illustratie, geen interactieve kaart nodig op een detailscherm
    }

    private var splitsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pace per kilometer")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(CozyPalette.textPrimary)

            VStack(spacing: 0) {
                ForEach(Array(splits.enumerated()), id: \.element.id) { index, split in
                    if index > 0 {
                        Divider().opacity(0.5)
                    }
                    HStack {
                        Text("Km \(split.kilometer)")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(CozyPalette.textPrimary)
                        Spacer()
                        Text(distanceUnit.formatPace(secPerKm: split.paceSecPerKm))
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(CozyPalette.speed)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .cozyCard()
    }

    private var effortCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(CozyPalette.speed.opacity(0.2))
                    .frame(width: 40, height: 40)
                Image(systemName: run.effortType.isInterval ? "arrow.left.arrow.right" : "bolt.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CozyPalette.speed)
            }
            Text(run.effortType.isTempo ? "This was a tempo run" : "This was an interval training")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textPrimary)
            Spacer()
        }
        .cozyCard()
    }

    private var contributionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Contribution to your stats")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(CozyPalette.textPrimary)

            contributionRow(
                icon: "flame.fill", color: CozyPalette.stamina,
                text: String(format: String(localized: "+%@ toward your weekly volume", comment: "e.g. '+5.02 km toward your weekly volume'"), distanceUnit.format(km: run.distanceKm))
            )

            if let weekRunNumber {
                contributionRow(
                    icon: "calendar", color: CozyPalette.consistency,
                    text: String(format: String(localized: "Your %@ run this week", comment: "e.g. 'Your 2nd run this week'"), ordinalText(weekRunNumber))
                )
            }

            if let bonusActiveUntil {
                contributionRow(
                    icon: "bolt.fill", color: CozyPalette.speed,
                    text: String(format: String(localized: "Speed bonus active through %@", comment: "e.g. 'Speed bonus active through Mar 12, 2026'"), bonusActiveUntil.formatted(date: .abbreviated, time: .omitted))
                )
            }
        }
        .cozyCard()
    }

    private func contributionRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(text)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(CozyPalette.textPrimary)
            Spacer()
        }
    }

    private var xpCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(CozyPalette.level.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: "star.fill")
                    .foregroundStyle(CozyPalette.level)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(countsForXP ? "+\(xpEarned.formatted()) XP" : "\(xpEarned.formatted()) XP")
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(CozyPalette.textPrimary)
                if !countsForXP {
                    Text("Doesn't count — this run was from before you first opened the app")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(CozyPalette.textSecondary)
                }
            }
            Spacer()
        }
        .cozyCard()
    }
}

#Preview {
    NavigationStack {
        RunDetailView(run: RunWorkout(
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            distanceMeters: 5020,
            durationSeconds: 1740,
            effortType: RunEffortType(isTempo: true, isInterval: false)
        ))
    }
}
