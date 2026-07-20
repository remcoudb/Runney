import Foundation
import HealthKit
import CoreLocation
import Combine

/// Enige toegangspoort tot HealthKit in de app. De rest van de app werkt
/// alleen met `RunWorkout`, nooit direct met `HKWorkout`.
@MainActor
final class HealthKitManager: ObservableObject {

    static let shared = HealthKitManager()

    private let store = HKHealthStore()

    @Published private(set) var isAuthorized = false
    @Published private(set) var runs: [RunWorkout] = []
    /// Volledige hardloophistorie uit HealthKit, zonder datumgrens. Bewust géén tempo/interval-
    /// classificatie (dat zou voor jarenlange historie veel te veel losse queries kosten — zie
    /// classifyEffort/effortClassificationLookbackDays). Gebruikt voor alles wat puur op
    /// afstand/datum/cumulatief volume draait: badges en de Loopstats-tab. De live GameEngine-
    /// scores (stamina/consistentie/snelheid) blijven op `runs` draaien, niet op deze lijst.
    @Published private(set) var lifetimeRuns: [RunWorkout] = []
    @Published private(set) var isLoading = false
    @Published var lastError: String?

    private let workoutType = HKObjectType.workoutType()
    private let distanceType = HKQuantityType(.distanceWalkingRunning)

    private init() {}

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Vraagt leesrechten voor workouts en afstand.
    func requestAuthorization() async {
        guard isHealthDataAvailable else {
            lastError = "HealthKit is niet beschikbaar op dit apparaat."
            return
        }

        let readTypes: Set<HKObjectType> = [
            workoutType,
            distanceType,
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKSeriesType.workoutRoute()
        ]

        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            isAuthorized = false
        }
    }

    /// Haalt alle hardloop-workouts op sinds een gegeven datum. Standaard: het vroegste van
    /// (90 dagen geleden, AppInstallDate) — puur "90 dagen geleden" zou XP laten wegvallen
    /// voor een gebruiker die de app langer dan 90 dagen geleden installeerde, omdat runs
    /// tussen installatie en "90 dagen geleden" dan nooit opgehaald worden.
    /// Voor runs binnen `GameConstants.effortClassificationLookbackDays` wordt ook het
    /// type inspanning (tempoloop/interval) bepaald — dat kost een extra query per run,
    /// dus doen we dat bewust niet voor de volledige historie.
    func fetchRuns(since startDate: Date? = nil) async {
        let effectiveStart = startDate ?? Swift.min(
            Calendar.current.date(byAdding: .day, value: -90, to: Date())!,
            AppInstallDate.value
        )
        isLoading = true
        defer { isLoading = false }

        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let datePredicate = HKQuery.predicateForSamples(withStart: effectiveStart, end: Date(), options: .strictStartDate)
        let combined = NSCompoundPredicate(andPredicateWithSubpredicates: [runningPredicate, datePredicate])

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        do {
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(
                    sampleType: workoutType,
                    predicate: combined,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [sortDescriptor]
                ) { _, samples, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: samples ?? [])
                    }
                }
                store.execute(query)
            }

            let workouts = samples.compactMap { $0 as? HKWorkout }
            let classificationCutoff = Calendar.current.date(
                byAdding: .day,
                value: -GameConstants.effortClassificationLookbackDays,
                to: Date()
            )!

            // Parallel via TaskGroup i.p.v. sequentieel: classifyEffort/fetchDistanceSamples zijn
            // hieronder `nonisolated` gemaakt (ze raken alleen onveranderlijke `let`-properties
            // aan zoals `store`), dus deze queries hoeven niet één voor één via de @MainActor.
            // HKHealthStore is thread-safe voor gelijktijdige queries — zie Apple-documentatie.
            // Blijft vanzelf begrensd: alleen runs binnen het classificatie-lookbackvenster
            // (standaard 30 dagen) doen hier een query, oudere runs krijgen direct .none.
            var classifiedRuns: [RunWorkout] = []
            classifiedRuns.reserveCapacity(workouts.count)

            await withTaskGroup(of: RunWorkout.self) { group in
                for workout in workouts {
                    group.addTask {
                        let effort: RunEffortType
                        if workout.startDate >= classificationCutoff {
                            effort = await self.classifyEffort(for: workout)
                        } else {
                            effort = .none
                        }
                        return RunWorkout(workout: workout, effortType: effort)
                    }
                }
                for await run in group {
                    classifiedRuns.append(run)
                }
            }
            // TaskGroup-resultaten komen binnen in voltooiingsvolgorde, niet in startvolgorde —
            // hersorteren om de bestaande "nieuwste eerst"-volgorde te garanderen.
            classifiedRuns.sort { $0.startDate > $1.startDate }

            self.runs = classifiedRuns
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    /// Haalt de volledige hardloophistorie op, zonder datumgrens en zonder classificatie —
    /// zie de uitleg bij `lifetimeRuns`. Fouten hier worden bewust niet in `lastError` gezet:
    /// dat veld voedt de foutstaat van de Runs-lijst/hoofd-flow, en een probleem hier mag
    /// die niet blokkeren (badges/loopstats zijn secundair aan de kernervaring).
    func fetchLifetimeRuns() async {
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        do {
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(
                    sampleType: workoutType,
                    predicate: runningPredicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [sortDescriptor]
                ) { _, samples, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: samples ?? [])
                    }
                }
                store.execute(query)
            }
            let workouts = samples.compactMap { $0 as? HKWorkout }
            self.lifetimeRuns = workouts.map { RunWorkout(workout: $0, effortType: .none) }
        } catch {
            // Stil falen — zie doc-comment hierboven.
        }
    }

    /// Ververst zowel het rollende venster (`runs`, motor achter de live GameEngine-scores)
    /// als de volledige historie (`lifetimeRuns`, motor achter badges/loopstats) in één keer.
    /// Gebruik dit i.p.v. losse `fetchRuns()`-aanroepen in `.task`/`.refreshable`, anders
    /// blijven badges en loopstats achter bij wat de gebruiker net ververst heeft.
    func refreshAll() async {
        async let recent: () = fetchRuns()
        async let lifetime: () = fetchLifetimeRuns()
        _ = await (recent, lifetime)
    }

    /// Handig gemak-endpoint: vraagt autorisatie aan (indien nodig) en haalt daarna direct de runs op.
    func setupAndFetch() async {
        await requestAuthorization()
        guard isAuthorized else { return }
        await refreshAll()
    }

    // MARK: - Tempo/interval classificatie

    /// Bepaalt of een workout een tempoloop en/of intervaltraining bevat, gebaseerd op hoe
    /// het tempo binnen de run varieert. Simpele heuristiek voor de proof-of-concept.
    /// `nonisolated` zodat gelijktijdige TaskGroup-taken (zie fetchRuns) niet alsnog serieel
    /// via de @MainActor afgehandeld worden — deze methode en de methodes die 'm aanroepen
    /// raken alleen onveranderlijke `let`-properties aan (store, workoutType, distanceType).
    private nonisolated func classifyEffort(for workout: HKWorkout) async -> RunEffortType {
        let segments = await fetchPaceSegments(for: workout)
        guard segments.count >= 2 else { return .none }

        let isTempo = hasSteadyFastSegment(segments)
        let isInterval = hasVaryingPace(segments)
        return RunEffortType(isTempo: isTempo, isInterval: isInterval)
    }

    /// Leest de losse afstand-samples die tijdens de workout gelogd zijn (Apple Watch logt
    /// doorgaans om de minuut of zo) en zet ze om naar (duur, tempo) segmenten.
    private nonisolated func fetchPaceSegments(for workout: HKWorkout) async -> [(durationSeconds: Double, paceSecPerKm: Double)] {
        let samples = await fetchDistanceSamples(for: workout)
        return samples.compactMap { sample -> (durationSeconds: Double, paceSecPerKm: Double)? in
            let meters = sample.quantity.doubleValue(for: .meter())
            let seconds = sample.endDate.timeIntervalSince(sample.startDate)
            guard meters > 0, seconds > 0 else { return nil }
            let km = meters / 1000
            return (durationSeconds: seconds, paceSecPerKm: seconds / km)
        }
    }

    /// Gedeelde ruwe afstand-sample-query, gebruikt door zowel de tempo/interval-classificatie
    /// als de kilometer-split-berekening — zo wordt dezelfde data maar op één plek opgehaald.
    private nonisolated func fetchDistanceSamples(for workout: HKWorkout) async -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForObjects(from: workout)
        do {
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(
                    sampleType: distanceType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
                ) { _, samples, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: samples ?? [])
                    }
                }
                store.execute(query)
            }
            return samples.compactMap { $0 as? HKQuantitySample }
        } catch {
            return []
        }
    }

    /// Tempoloop: een aaneengesloten reeks segmenten van samen 20+ minuten met een tempo
    /// dat gelijkmatig blijft (lage variatie) én sneller is dan het "makkelijke tempo".
    private nonisolated func hasSteadyFastSegment(_ segments: [(durationSeconds: Double, paceSecPerKm: Double)]) -> Bool {
        let minDuration = GameConstants.tempoMinDurationMinutes * 60
        var windowStart = 0
        var windowDuration = 0.0
        var windowPaces: [Double] = []

        for segment in segments {
            windowDuration += segment.durationSeconds
            windowPaces.append(segment.paceSecPerKm)

            while windowDuration >= minDuration {
                let mean = windowPaces.reduce(0, +) / Double(windowPaces.count)
                let variance = windowPaces.reduce(0) { $0 + pow($1 - mean, 2) } / Double(windowPaces.count)
                let coefficientOfVariation = mean > 0 ? sqrt(variance) / mean : 0

                if coefficientOfVariation <= GameConstants.tempoMaxPaceVariance && mean < GameConstants.beginnerPaceSecPerKm {
                    return true
                }

                // Schuif het venster op: oudste segment eruit, opnieuw proberen.
                windowDuration -= segments[windowStart].durationSeconds
                windowPaces.removeFirst()
                windowStart += 1
            }
        }
        return false
    }

    /// Intervaltraining: het tempo varieert sterk over de hele run (hoge variatiecoëfficiënt),
    /// met genoeg segmenten om dat betrouwbaar te kunnen zeggen. Twee extra filters t.o.v. een
    /// kale variatiecheck: te korte (ruizige) segmenten tellen niet mee, en er moet een
    /// herhaald patroon van duidelijk snellere segmenten zijn — niet slechts één uitschieter.
    private nonisolated func hasVaryingPace(_ segments: [(durationSeconds: Double, paceSecPerKm: Double)]) -> Bool {
        let reliableSegments = segments.filter { $0.durationSeconds >= GameConstants.intervalSegmentMinDurationSeconds }
        guard reliableSegments.count >= GameConstants.intervalMinSegmentCount else { return false }

        let paces = reliableSegments.map { $0.paceSecPerKm }
        let mean = paces.reduce(0, +) / Double(paces.count)
        guard mean > 0 else { return false }
        let variance = paces.reduce(0) { $0 + pow($1 - mean, 2) } / Double(paces.count)
        let stdev = sqrt(variance)
        let coefficientOfVariation = stdev / mean

        guard coefficientOfVariation >= GameConstants.intervalMinPaceVariance else { return false }

        // Bevestig dat het om een herhaald patroon gaat: meerdere segmenten die duidelijk
        // sneller zijn dan gemiddeld, niet één toevallige sprint (stoplicht, GPS-fout).
        let fastThreshold = mean - stdev * 0.5
        let fastSegmentCount = paces.filter { $0 < fastThreshold }.count
        return fastSegmentCount >= GameConstants.intervalMinFastSegments
    }

    // MARK: - Kilometer-splits

    /// Berekent het tempo per volledige kilometer binnen een run, door de cumulatieve
    /// afstand-over-tijd te reconstrueren uit de ruwe HealthKit-samples en te interpoleren
    /// op welk moment elke kilometer-grens gepasseerd werd.
    func fetchKilometerSplits(for workoutID: UUID) async -> [RunSplit] {
        guard let workout = await fetchWorkout(withID: workoutID) else { return [] }
        let samples = await fetchDistanceSamples(for: workout)
        guard !samples.isEmpty else { return [] }

        var timeline: [(time: Date, cumulativeMeters: Double)] = [(workout.startDate, 0)]
        var cumulative = 0.0
        for sample in samples {
            cumulative += sample.quantity.doubleValue(for: .meter())
            timeline.append((sample.endDate, cumulative))
        }

        let totalKm = Int(cumulative / 1000)
        guard totalKm >= 1 else { return [] }

        var splits: [RunSplit] = []
        var previousTime = workout.startDate
        for km in 1...totalKm {
            guard let markTime = time(atDistance: Double(km) * 1000, in: timeline) else { break }
            let paceSeconds = markTime.timeIntervalSince(previousTime)
            splits.append(RunSplit(kilometer: km, paceSecPerKm: paceSeconds))
            previousTime = markTime
        }
        return splits
    }

    /// Lineaire interpolatie: op welk tijdstip werd `targetMeters` bereikt, gegeven de
    /// cumulatieve-afstand-tijdlijn? Nodig omdat samples zelden precies op een km-grens vallen.
    private func time(atDistance targetMeters: Double, in timeline: [(time: Date, cumulativeMeters: Double)]) -> Date? {
        guard let first = timeline.first else { return nil }
        if targetMeters <= first.cumulativeMeters { return first.time }

        for i in 1..<timeline.count {
            let previous = timeline[i - 1]
            let current = timeline[i]
            guard targetMeters <= current.cumulativeMeters else { continue }
            guard current.cumulativeMeters > previous.cumulativeMeters else { return current.time }

            let fraction = (targetMeters - previous.cumulativeMeters) / (current.cumulativeMeters - previous.cumulativeMeters)
            let interval = current.time.timeIntervalSince(previous.time) * fraction
            return previous.time.addingTimeInterval(interval)
        }
        return nil
    }

    // MARK: - Route (kaartje)

    /// Haalt de GPS-route van een run op, indien die met locatiegegevens gelogd is (dus niet
    /// bij loopband-runs of handmatig ingevoerde runs — dan komt hier gewoon een lege array uit).
    func fetchRoute(for workoutID: UUID) async -> [CLLocationCoordinate2D] {
        guard let workout = await fetchWorkout(withID: workoutID) else { return [] }

        let routePredicate = HKQuery.predicateForObjects(from: workout)
        let routeSamples: [HKWorkoutRoute]
        do {
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(
                    sampleType: HKSeriesType.workoutRoute(),
                    predicate: routePredicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { _, samples, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: samples ?? [])
                    }
                }
                store.execute(query)
            }
            routeSamples = samples.compactMap { $0 as? HKWorkoutRoute }
        } catch {
            return []
        }

        guard let route = routeSamples.first else { return [] }

        var locations: [CLLocation] = []
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let routeQuery = HKWorkoutRouteQuery(route: route) { _, result, done, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    if let result {
                        locations.append(contentsOf: result)
                    }
                    if done {
                        continuation.resume(returning: ())
                    }
                }
                store.execute(routeQuery)
            }
        } catch {
            return []
        }

        return locations.map { $0.coordinate }
    }

    // MARK: - Gedeeld

    /// RunWorkout houdt bewust geen HealthKit-object vast (zie RunWorkout.swift) — voor acties
    /// die het originele HKWorkout nodig hebben (splits, route) zoeken we 'm hier terug op ID.
    private func fetchWorkout(withID id: UUID) async -> HKWorkout? {
        let predicate = HKQuery.predicateForObject(with: id)
        do {
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(
                    sampleType: workoutType,
                    predicate: predicate,
                    limit: 1,
                    sortDescriptors: nil
                ) { _, samples, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: samples ?? [])
                    }
                }
                store.execute(query)
            }
            return samples.first as? HKWorkout
        } catch {
            return nil
        }
    }
}
