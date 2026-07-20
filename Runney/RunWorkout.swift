import Foundation
import HealthKit

/// Een gestandaardiseerde representatie van een hardlooprun,
/// omgezet vanuit een HKWorkout zodat de rest van de app niets
/// van HealthKit hoeft te weten.
/// `nonisolated`: wordt overal gebruikt binnen GameEngine/BadgeDefinition/PersonalRecords,
/// die zelf nonisolated zijn en aangeroepen worden binnen GameStatsStore's Task.detached —
/// zonder dit zouden ook simpele property-lookups als `.distanceKm` daar niet compileren.
nonisolated struct RunWorkout: Identifiable, Hashable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let distanceMeters: Double
    let durationSeconds: Double
    /// Classificatie (tempoloop/intervaltraining) t.b.v. de Snelheid-score. Zie GameEngine.
    let effortType: RunEffortType
    /// Actieve calorieën, indien de bron dit heeft gelogd (niet elke app/toestel doet dit consistent).
    let caloriesBurned: Double?
    /// Gemiddelde hartslag (bpm), indien beschikbaar.
    let averageHeartRate: Double?

    /// Gemiddeld tempo in seconden per kilometer.
    var averagePaceSecPerKm: Double {
        guard distanceKm > 0 else { return 0 }
        return durationSeconds / distanceKm
    }

    var distanceKm: Double {
        distanceMeters / 1000
    }

    /// `nonisolated`: wordt aangeroepen vanuit de nonisolated TaskGroup-taken in
    /// HealthKitManager.fetchRuns (parallelle effort-classificatie) — zie daar voor context.
    nonisolated init(workout: HKWorkout, effortType: RunEffortType = .none) {
        self.id = workout.uuid
        self.startDate = workout.startDate
        self.endDate = workout.endDate
        self.durationSeconds = workout.duration
        self.distanceMeters = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?
            .sumQuantity()?
            .doubleValue(for: .meter()) ?? 0
        self.caloriesBurned = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie())
        self.averageHeartRate = workout.statistics(for: HKQuantityType(.heartRate))?
            .averageQuantity()?
            .doubleValue(for: HKUnit(from: "count/min"))
        self.effortType = effortType
    }

    /// Handig voor previews en unit tests, zonder een echte HKWorkout nodig te hebben.
    init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date,
        distanceMeters: Double,
        durationSeconds: Double,
        effortType: RunEffortType = .none,
        caloriesBurned: Double? = nil,
        averageHeartRate: Double? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.effortType = effortType
        self.caloriesBurned = caloriesBurned
        self.averageHeartRate = averageHeartRate
    }
}
