import Foundation
import Combine

/// Beheert de lijst met door de gebruiker zelf ingevoerde geplande runs. Net als RaceGoal
/// lokaal opgeslagen (UserDefaults, JSON-encoded) — er is geen server nodig voor iets dat
/// toch alleen door de gebruiker zelf ingevuld en gelezen wordt, en dat past bij de "alles
/// blijft op je toestel"-aanpak van de rest van de app.
@MainActor
final class PlannedRunStore: ObservableObject {
    static let shared = PlannedRunStore()

    /// Altijd oplopend op datum gesorteerd, zodat elke lijst-view die dit rechtstreeks toont
    /// niet zelf nog hoeft te sorteren.
    @Published private(set) var plannedRuns: [PlannedRun] = []

    private static let storageKey = "plannedRunsData"

    private init() {
        plannedRuns = Self.load()
    }

    func add(_ run: PlannedRun) {
        plannedRuns.append(run)
        sortAndSave()
    }

    func update(_ run: PlannedRun) {
        guard let index = plannedRuns.firstIndex(where: { $0.id == run.id }) else { return }
        plannedRuns[index] = run
        sortAndSave()
    }

    func delete(_ run: PlannedRun) {
        plannedRuns.removeAll { $0.id == run.id }
        save()
    }

    /// Voegt toe als het id nog niet bestaat, overschrijft anders — gebruikt bij het
    /// importeren van een gedeelde link (zie PlannedRunSharing), zodat je dezelfde link
    /// gerust nog een keer kunt openen zonder dat er duplicaten ontstaan.
    func upsert(_ run: PlannedRun) {
        if plannedRuns.contains(where: { $0.id == run.id }) {
            update(run)
        } else {
            add(run)
        }
    }

    /// Of een gegeven id al bestaat — gebruikt door het importscherm om vooraf te laten zien
    /// hoeveel van de binnenkomende runs nieuw zijn versus een update van iets bestaands.
    func exists(_ id: UUID) -> Bool {
        plannedRuns.contains { $0.id == id }
    }

    /// De geplande run van een specifieke dag, indien aanwezig — voor de "Vandaag gepland"-
    /// kaart op Home. Ervan uitgaand dat er maximaal één geplande run per dag is (de vorm
    /// dwingt dat niet expliciet af, maar dat is hoe trainingsschema's doorgaans werken).
    func plannedRun(for date: Date, calendar: Calendar = .current) -> PlannedRun? {
        plannedRuns.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    private func sortAndSave() {
        plannedRuns.sort { $0.date < $1.date }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(plannedRuns) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func load() -> [PlannedRun] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PlannedRun].self, from: data) else { return [] }
        return decoded.sorted { $0.date < $1.date }
    }
}
