import SwiftUI
import UIKit
import MessageUI

// MARK: - Personalisatie

/// Naam, uiterlijk (licht/donker), achtergrondkleur, en de mascotte-schakelaar — alles wat
/// puur over "hoe voelt de app aan" gaat, los van trainingsinstellingen of accountzaken.
struct PersonalizationSettingsView: View {
    @AppStorage("userName") private var userName: String = "Runner"
    @AppStorage(backgroundThemeStorageKey) private var backgroundThemeRaw: String = BackgroundTheme.cream.rawValue
    @AppStorage(appearanceOverrideStorageKey) private var appearanceRaw: String = AppearanceOverride.system.rawValue
    @AppStorage(showsMascotStorageKey) private var showsMascot: Bool = true
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                nameCard
                appearanceCard
                themeCard
                mascotCard
            }
            .padding(20)
        }
        .cozyBackground()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Personalization")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your name")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textSecondary)

            TextField("Name", text: $userName)
                .focused($nameFieldFocused)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(CozyPalette.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background((BackgroundTheme(rawValue: backgroundThemeRaw) ?? .cream).color)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .submitLabel(.done)
                .onSubmit { nameFieldFocused = false }
                .autocorrectionDisabled()

            Text("This is the name used in the greeting on Home.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)
        }
        .cozyCard()
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Appearance")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textSecondary)

            Picker("", selection: $appearanceRaw) {
                ForEach(AppearanceOverride.allCases) { option in
                    Label(option.displayName, systemImage: option.icon).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Text("\"System\" follows your device's own light/dark setting.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)
        }
        .cozyCard()
    }

    private var themeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Background color")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textSecondary)

            HStack(spacing: 16) {
                ForEach(BackgroundTheme.allCases) { theme in
                    themeSwatch(theme)
                }
                Spacer()
            }

            Text("Applies to the whole app.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)
        }
        .cozyCard()
    }

    private func themeSwatch(_ theme: BackgroundTheme) -> some View {
        let isSelected = backgroundThemeRaw == theme.rawValue

        return Button {
            backgroundThemeRaw = theme.rawValue
        } label: {
            Circle()
                .fill(theme.color)
                .frame(width: 44, height: 44)
                .overlay(
                    Circle()
                        .stroke(CozyPalette.textPrimary, lineWidth: isSelected ? 2.5 : 0)
                        .padding(-3)
                )
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CozyPalette.textPrimary)
                        .opacity(isSelected ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.displayName)
    }

    private var mascotCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $showsMascot) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show mascot")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(CozyPalette.textPrimary)
                    Text("Turns off the raccoon in onboarding, celebrations, empty states, and run recaps.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(CozyPalette.textSecondary)
                }
            }
            .tint(CozyPalette.stamina)
        }
        .cozyCard()
    }
}

// MARK: - Training

/// Alles wat met de daadwerkelijke trainingsinstellingen te maken heeft — eenheid, of level
/// zichtbaar is op Home, en het wedstrijddoel.
struct TrainingSettingsView: View {
    @AppStorage(distanceUnitStorageKey) private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue
    @AppStorage(showsLevelOnHomeStorageKey) private var showsLevelOnHome: Bool = true
    @ObservedObject private var store = GameStatsStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                distanceUnitCard
                homeDisplayCard
                raceGoalCard
            }
            .padding(20)
        }
        .cozyBackground()
        .navigationTitle("Training")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var distanceUnitCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Distance unit")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.textSecondary)

            Picker("", selection: $distanceUnitRaw) {
                ForEach(DistanceUnit.allCases) { unit in
                    Text(unit.displayName).tag(unit.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Text("Applies to all distances and paces shown in the app.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)
        }
        .cozyCard()
    }

    private var homeDisplayCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $showsLevelOnHome) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show level on Home")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(CozyPalette.textPrimary)
                    Text("Turns off the level card and level-up celebration, if you'd rather focus on your stats.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(CozyPalette.textSecondary)
                }
            }
            .tint(CozyPalette.stamina)
        }
        .cozyCard()
    }

    private var raceGoalCard: some View {
        ProGate(
            title: String(localized: "Race Readiness", comment: "Pro feature title"),
            subtitle: String(localized: "Know exactly how ready you are for race day.", comment: "Pro feature subtitle"),
            icon: "flag.checkered"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Race goal")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(CozyPalette.textSecondary)

                if let goal = store.raceGoal {
                    RaceGoalEditor(goal: goal, onChange: { store.raceGoal = $0 })

                    Button(role: .destructive) {
                        store.raceGoal = nil
                    } label: {
                        Text("Remove race goal")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                    }
                } else {
                    Button {
                        store.raceGoal = RaceGoal(
                            distanceType: .half,
                            customKm: 21.1,
                            raceDate: Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
                        )
                    } label: {
                        Text("Set a race goal")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(CozyPalette.primaryButtonText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(CozyPalette.primaryButtonBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                Text("Determines your race readiness score on Home and Stats.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(CozyPalette.textSecondary)
            }
            .cozyCard()
        }
    }
}

// MARK: - Notificaties

struct NotificationSettingsView: View {
    @AppStorage("weeklyRecapNotificationsEnabled") private var weeklyRecapNotificationsEnabled: Bool = false
    @ObservedObject private var notifications = NotificationManager.shared
    @State private var showsNotificationDeniedAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                notificationsCard
            }
            .padding(20)
        }
        .cozyBackground()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Vangt af dat de gebruiker meldingen buiten de app om (in Instellingen) heeft
            // uitgezet nadat de toggle hier al aanstond — anders blijft de toggle "aan"
            // getoond terwijl er feitelijk nooit meer een melding komt.
            await notifications.refreshAuthorizationStatus()
            if weeklyRecapNotificationsEnabled && !notifications.isAuthorized {
                weeklyRecapNotificationsEnabled = false
                notifications.cancelWeeklyRecapNotification()
            }
        }
    }

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: weeklyRecapToggleBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly recap")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(CozyPalette.textPrimary)
                    Text("A notification every Sunday at 8 PM that your weekly recap is ready.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(CozyPalette.textSecondary)
                }
            }
            .tint(CozyPalette.stamina)
        }
        .cozyCard()
        .alert("Notifications are off", isPresented: $showsNotificationDeniedAlert) {
            Button("Go to Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Turn on notifications for Runney in Settings to receive the weekly recap.")
        }
    }

    /// Aparte binding i.p.v. rechtstreeks aan weeklyRecapNotificationsEnabled — het aanzetten
    /// vraagt eerst asynchroon toestemming, en moet de toggle terugzetten als die geweigerd wordt.
    private var weeklyRecapToggleBinding: Binding<Bool> {
        Binding(
            get: { weeklyRecapNotificationsEnabled },
            set: { newValue in
                if newValue {
                    Task {
                        let granted = await notifications.requestAuthorization()
                        if granted {
                            weeklyRecapNotificationsEnabled = true
                            notifications.scheduleWeeklyRecapNotification()
                        } else {
                            weeklyRecapNotificationsEnabled = false
                            showsNotificationDeniedAlert = true
                        }
                    }
                } else {
                    weeklyRecapNotificationsEnabled = false
                    notifications.cancelWeeklyRecapNotification()
                }
            }
        )
    }
}

// MARK: - Ondersteuning

struct SupportSettingsView: View {
    let onResetOnboarding: () -> Void

    @State private var showsMailCompose = false
    @State private var showsMailUnavailableAlert = false
    /// TIJDELIJK — puur om RunRecapView te kunnen testen zonder een echte run vandaag.
    /// Verwijder deze knop + mockRunRecapView weer zodra je 'm niet meer nodig hebt.
    @State private var showsRecapDebug = false

    /// Vervang dit door je eigen contactadres voordat je naar de App Store publiceert —
    /// dit adres wordt ook elders gebruikt als App Store Connect's verplichte support-contact.
    private let feedbackEmail = "your-email@example.com"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                feedbackCard
                recapDebugButton
                resetOnboardingButton
            }
            .padding(20)
        }
        .cozyBackground()
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var feedbackCard: some View {
        Button {
            if MFMailComposeViewController.canSendMail() {
                showsMailCompose = true
            } else {
                openMailtoFallback()
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(CozyPalette.stamina.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: "envelope.fill")
                        .foregroundStyle(CozyPalette.stamina)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Send Feedback")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(CozyPalette.textPrimary)
                    Text("Report a bug or suggest a feature")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(CozyPalette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CozyPalette.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .cozyCard()
        .sheet(isPresented: $showsMailCompose) {
            FeedbackMailView(recipient: feedbackEmail, subject: feedbackSubject, body: feedbackBody)
        }
        .alert("Couldn't Open Mail", isPresented: $showsMailUnavailableAlert) {
            Button("Copy Email Address") {
                UIPasteboard.general.string = feedbackEmail
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("No mail app is set up on this device. You can reach us at \(feedbackEmail).")
        }
    }

    private var feedbackSubject: String {
        "Runney feedback"
    }

    /// Voegt app-versie/build/toestel-info toe onder een scheidingslijntje — handig voor jou
    /// als ontvanger, zonder dat de gebruiker dit zelf hoeft over te typen. De gebruiker typt
    /// z'n feedback gewoon bovenaan, boven de lijn.
    private var feedbackBody: String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        return """


        ---
        App version: \(appVersion) (\(buildNumber))
        iOS: \(UIDevice.current.systemVersion)
        Device: \(UIDevice.current.model)
        """
    }

    /// Terugvalroute als er geen Mail-account is ingesteld op dit toestel (canSendMail() is
    /// dan false) — probeert alsnog een mailto:-link te openen (bv. als de gebruiker Gmail of
    /// Outlook als losse app heeft), en toont anders een alert met het adres om te kopiëren.
    private func openMailtoFallback() {
        let subjectEncoded = feedbackSubject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let bodyEncoded = feedbackBody.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "mailto:\(feedbackEmail)?subject=\(subjectEncoded)&body=\(bodyEncoded)"),
              UIApplication.shared.canOpenURL(url) else {
            showsMailUnavailableAlert = true
            return
        }
        UIApplication.shared.open(url)
    }

    /// TIJDELIJK — zie de @State-declaratie hierboven voor waarom.
    private var recapDebugButton: some View {
        Button {
            showsRecapDebug = true
        } label: {
            HStack {
                Image(systemName: "sparkles")
                Text("Preview Run Recap (debug)")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
            }
            .foregroundStyle(CozyPalette.level)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .fullScreenCover(isPresented: $showsRecapDebug) {
            mockRunRecapView()
        }
    }

    /// De opbouw van de verzonnen data (met een `for`-lus) kan niet rechtstreeks in een
    /// ViewBuilder-closure staan zoals bij `.fullScreenCover { }` — vandaar hier als losse
    /// functie, die alleen de kant-en-klare view teruggeeft.
    private func mockRunRecapView() -> some View {
        let today = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: Date()) ?? Date()
        let mockRun = RunWorkout(
            startDate: today,
            endDate: today.addingTimeInterval(1980),
            distanceMeters: 6100,
            durationSeconds: 1980,
            effortType: RunEffortType(isTempo: true, isInterval: false)
        )
        let calendar = Calendar.current
        var mockHistory: [RunWorkout] = [mockRun]
        for weeksAgo in 0..<4 {
            for dayOffset in [1, 3, 5] {
                if let date = calendar.date(byAdding: .day, value: -(weeksAgo * 7 + dayOffset), to: Date()) {
                    mockHistory.append(RunWorkout(
                        startDate: date,
                        endDate: date.addingTimeInterval(1800),
                        distanceMeters: 5200,
                        durationSeconds: 1740
                    ))
                }
            }
        }
        let mockPlan = PlannedRun(date: today, distanceKm: 6.0, targetPaceSecPerKm: 330, label: "Tempo run")

        return RunRecapView(
            run: mockRun,
            allRuns: mockHistory,
            planComparison: mockPlan.comparison(against: mockHistory)
        )
    }

    private var resetOnboardingButton: some View {
        Button {
            onResetOnboarding()
        } label: {
            HStack {
                Image(systemName: "arrow.counterclockwise")
                Text("Restart onboarding (test)")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
            }
            .foregroundStyle(CozyPalette.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }
}

/// Wrapper rond Apple's MFMailComposeViewController — laat de gebruiker feedback sturen
/// zonder de app te verlaten, met het e-mailadres/onderwerp/versie-info al ingevuld.
private struct FeedbackMailView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.setToRecipients([recipient])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        controller.mailComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            dismiss()
        }
    }
}
