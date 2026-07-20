import Foundation
import Combine

/// Hoe zwaar een run voelde volgens de gebruiker zelf (RPE — Rate of Perceived Exertion),
/// niet iets dat uit HealthKit-data valt af te leiden. Bewust drie simpele niveaus i.p.v.
/// een fijnmazige schaal — makkelijker te kiezen ná een run, en elke gradatie krijgt een
/// eigen wasbeer-houding als visuele referentie in plaats van kale tekst.
enum PerceivedEffort: String, Codable, CaseIterable, Identifiable {
    case easy, medium, hard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .easy: return String(localized: "Easy", comment: "Perceived run effort")
        case .medium: return String(localized: "Medium", comment: "Perceived run effort")
        case .hard: return String(localized: "Tough", comment: "Perceived run effort")
        }
    }

    /// Oplopende inspanning in de houding zelf: rustig lopend → actief rennend → middenin
    /// een sprong. Hergebruikt gewoon de bestaande mascotte-poses, geen nieuwe assets nodig.
    var pose: MascotPose {
        switch self {
        case .easy: return .walking
        case .medium: return .running
        case .hard: return .leaping
        }
    }
}

/// Koppelt een PerceivedEffort-keuze aan een specifieke run (via UUID) — RunWorkout zelf komt
/// rechtstreeks uit HealthKit en is niet lokaal uit te breiden met een extra veld, dus dit
/// leeft in een eigen, kleine opslag ernaast. Zelfde eenvoudige UserDefaults+JSON-aanpak als
/// de rest van de app (PlannedRunStore, etc.) — geen server nodig voor iets dat puur lokaal is.
@MainActor
final class RunEffortStore: ObservableObject {
    static let shared = RunEffortStore()

    private let storageKey = "runPerceivedEffort"

    @Published private(set) var ratings: [UUID: PerceivedEffort] = [:]

    private init() {
        load()
    }

    func effort(for runID: UUID) -> PerceivedEffort? {
        ratings[runID]
    }

    func setEffort(_ effort: PerceivedEffort, for runID: UUID) {
        ratings[runID] = effort
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([UUID: PerceivedEffort].self, from: data)
        else { return }
        ratings = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(ratings) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
