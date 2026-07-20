import Foundation
import UserNotifications
import Combine

/// Enige toegangspoort tot lokale notificaties in de app — vergelijkbaar met hoe
/// HealthKitManager de enige toegangspoort tot HealthKit is.
@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    /// Identifier van de terugkerende wekelijkse-samenvatting-melding, zodat we 'm gericht
    /// kunnen updaten/verwijderen zonder eventuele toekomstige, andere notificaties te raken.
    private static let weeklyRecapIdentifier = "weeklyRecapReminder"

    @Published private(set) var isAuthorized = false

    private override init() {
        super.init()
        // Zonder dit als delegate blijft een melding onzichtbaar als de app toevallig al open
        // staat op het triggermoment — zie userNotificationCenter(_:willPresent:...) hieronder.
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshAuthorizationStatus() }
    }

    /// Vraagt toestemming voor notificaties. Geeft terug of het gelukt is — bij `false` moet
    /// de aanroeper de gebruiker naar Instellingen verwijzen, want iOS toont de systeemprompt
    /// nooit een tweede keer nadat 'm één keer geweigerd is.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            return granted
        } catch {
            isAuthorized = false
            return false
        }
    }

    /// Haalt de daadwerkelijke systeemstatus op — nodig omdat de gebruiker meldingen ook via
    /// Instellingen (buiten de app om) kan uitzetten, wat @Published var isAuthorized niet
    /// vanzelf zou merken.
    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    /// Plant een terugkerende melding elke zondag om 20:00 dat de wekelijkse samenvatting
    /// klaarstaat — zondag is de laatste dag van een maandag-startende week, dus vlak voordat
    /// de week omslaat en de "Deze week"-kaart op Home weer bij nul begint.
    func scheduleWeeklyRecapNotification() {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Weekly recap", comment: "Notification title")
        content.body = String(localized: "Your weekly recap is ready — see what you've built up this week.", comment: "Notification body")
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.weekday = 1 // zondag — UNCalendarNotificationTrigger gebruikt altijd de
                                    // Gregoriaanse telling (1 = zondag), ongeacht locale-instelling.
        dateComponents.hour = 20
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: Self.weeklyRecapIdentifier, content: content, trigger: trigger)

        // Eerst verwijderen i.p.v. blind toevoegen: voorkomt dubbele/verouderde triggers als
        // dit vaker aangeroepen wordt (bv. elke keer dat Profiel geopend wordt terwijl de
        // toggle al aanstond).
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.weeklyRecapIdentifier])
        center.add(request)
    }

    func cancelWeeklyRecapNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.weeklyRecapIdentifier])
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// `nonisolated` omdat UNUserNotificationCenter dit vanaf een systeem-thread aanroept,
    /// niet noodzakelijk de MainActor — de closure raakt geen actor-isolated state aan.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
