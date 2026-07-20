import SwiftUI

@main
struct RunneyApp: App {
    /// nil zolang er geen (geldige) inkomende deellink verwerkt is. Bewust één optional i.p.v.
    /// een losse `[PlannedRun]?` + boolean-vlag: bij twee losse @State's kan het sheet al
    /// renderen vóórdat de tweede toewijzing is doorgekomen (vooral bij een koude appstart via
    /// de link), wat een leeg sheet oplevert. Eén Identifiable optional voorkomt die race
    /// volledig, want .sheet(item:) toont pas zodra de waarde zelf niet-nil is.
    @State private var incomingImport: IncomingPlanImport?
    @AppStorage(appearanceOverrideStorageKey) private var appearanceRaw: String = AppearanceOverride.system.rawValue

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .onOpenURL { url in
                    guard let plannedRuns = PlannedRunSharing.plannedRuns(from: url), !plannedRuns.isEmpty else { return }
                    incomingImport = IncomingPlanImport(plannedRuns: plannedRuns)
                }
                .sheet(item: $incomingImport) { importItem in
                    ImportPlannedRunsView(incomingPlannedRuns: importItem.plannedRuns)
                }
                // nil (bij "system") laat SwiftUI gewoon de systeeminstelling volgen — geen
                // aparte "doe niks"-tak nodig, .preferredColorScheme(nil) is precies dat.
                .preferredColorScheme((AppearanceOverride(rawValue: appearanceRaw) ?? .system).colorScheme)
        }
    }
}

/// Simpele Identifiable-wrapper — [PlannedRun] is zelf geen Identifiable, en .sheet(item:)
/// heeft dat nodig.
private struct IncomingPlanImport: Identifiable {
    let id = UUID()
    let plannedRuns: [PlannedRun]
}
