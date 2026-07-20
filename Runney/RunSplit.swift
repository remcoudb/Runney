import Foundation

/// Eén afgelegde kilometer binnen een run, met het tempo van precies dat stuk.
struct RunSplit: Identifiable {
    var id: Int { kilometer }
    let kilometer: Int
    let paceSecPerKm: Double
}
