import SwiftUI

/// Een "verhaal"-achtige terugblik op één specifieke run — een reeks schermen die je met een
/// tik of swipe doorloopt (zelfde gevoel als Instagram/Snapchat-stories), elk met een eigen
/// kleurthema. Bewust GEEN automatische tijd-gestuurde voortgang zoals bij social-media-
/// stories: de gebruiker bepaalt zelf het tempo, want dit gaat over cijfers die je even moet
/// kunnen lezen, niet over snel wegkijkende content.
struct RunRecapView: View {
    let run: RunWorkout
    let allRuns: [RunWorkout]
    let planComparison: PlannedRunComparison?
    /// nil als er geen actief wedstrijddoel is — dan wordt de race-gereedheid-pagina
    /// simpelweg overgeslagen, net als de planvergelijking-pagina zonder gekoppeld plan.
    var raceGoal: RaceGoal? = nil

    @Environment(\.dismiss) private var dismiss
    @AppStorage(distanceUnitStorageKey) private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue
    @State private var pageIndex = 0
    @State private var barsFilled = false
    @State private var closingLineDrawn = false
    @State private var closingTextShown = false
    @State private var closingButtonShown = false
    @ObservedObject private var effortStore = RunEffortStore.shared
    @State private var selectedEffort: PerceivedEffort?

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    private var contribution: RunContribution {
        GameEngine.runContribution(for: run, allRuns: allRuns)
    }

    /// Zelfde voor-en-na-truc als RunContribution, maar dan voor de racegereedheid-score —
    /// die leeft immers los van de gewone GameStats-berekening (heeft een eigen wedstrijd-
    /// doel als extra input) en wordt daarom apart berekend.
    private var raceReadinessDelta: (before: Int, after: Int)? {
        guard let raceGoal else { return nil }
        let before = GameEngine.raceReadiness(goal: raceGoal, runs: allRuns, now: run.startDate)
        let after = GameEngine.raceReadiness(goal: raceGoal, runs: allRuns, now: run.endDate)
        return (before.totalScore, after.totalScore)
    }

    /// De geplande-run-vergelijking hoort alleen bij déze terugblik als de gematchte run ook
    /// daadwerkelijk deze specifieke run is — anders (bij meerdere runs op één dag) zou de
    /// verkeerde run per ongeluk de planvergelijking van een andere run overnemen.
    private var relevantPlanComparison: PlannedRunComparison? {
        guard let planComparison, planComparison.matchedRun?.id == run.id else { return nil }
        return planComparison
    }

    private enum Page: Equatable {
        case intro, distancePace, effortRating, planComparison, contribution, raceReadiness, closing
    }

    private var pages: [Page] {
        var result: [Page] = [.intro, .distancePace, .effortRating]
        if relevantPlanComparison != nil {
            result.append(.planComparison)
        }
        result.append(.contribution)
        if raceReadinessDelta != nil {
            result.append(.raceReadiness)
        }
        result.append(.closing)
        return result
    }

    var body: some View {
        ZStack {
            backgroundColor(for: pages[pageIndex])
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.35), value: pageIndex)

            // Onzichtbare tik-zones voor voor-/achteruit — staan ONDER de topbar/knoppen in
            // de ZStack-volgorde hieronder, zodat die knoppen altijd voorrang krijgen bij het
            // bepalen welke laag een tik daadwerkelijk afhandelt.
            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { goBack() }
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { goForward() }
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                pageContent(for: pages[pageIndex])
                    .id(pageIndex)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                Spacer()
                Spacer()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width < -50 {
                        goForward()
                    } else if value.translation.width > 50 {
                        goBack()
                    }
                }
        )
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                barsFilled = true
            }
        }
    }

    // MARK: - Navigatie

    private func goForward() {
        guard pageIndex < pages.count - 1 else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            pageIndex += 1
        }
    }

    private func goBack() {
        guard pageIndex > 0 else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            pageIndex -= 1
        }
    }

    // MARK: - Topbar (voortgang + sluiten)

    private var topBar: some View {
        VStack(spacing: 14) {
            HStack(spacing: 5) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(index <= pageIndex ? 0.9 : 0.3))
                        .frame(height: 3)
                }
            }
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.white.opacity(0.15))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Achtergrondkleuren per pagina

    /// Bewust diepe, verzadigde tinten i.p.v. de zachte pastel-CozyPalette — dit is een
    /// vol-scherm "verhaal"-moment dat mag opvallen, anders dan de rustige, cozy kaarten
    /// elders in de app.
    private func backgroundColor(for page: Page) -> Color {
        switch page {
        case .intro: return Color(red: 0.13, green: 0.16, blue: 0.14)
        case .distancePace: return Color(red: 0.10, green: 0.28, blue: 0.20)
        case .effortRating: return Color(red: 0.20, green: 0.16, blue: 0.30)
        case .planComparison: return Color(red: 0.12, green: 0.20, blue: 0.34)
        case .contribution: return Color(red: 0.28, green: 0.19, blue: 0.10)
        case .raceReadiness: return Color(red: 0.30, green: 0.14, blue: 0.16)
        case .closing: return Color(red: 0.32, green: 0.24, blue: 0.08)
        }
    }

    // MARK: - Pagina-inhoud

    @ViewBuilder
    private func pageContent(for page: Page) -> some View {
        switch page {
        case .intro: introPage
        case .distancePace: distancePacePage
        case .effortRating: effortRatingPage
        case .planComparison: planComparisonPage
        case .contribution: contributionPage
        case .raceReadiness: raceReadinessPage
        case .closing: closingPage
        }
    }

    private var introPage: some View {
        VStack(spacing: 20) {
            Mascot(pose: .running, height: 90, tint: .white)
            Text(run.startDate.formatted(date: .complete, time: .omitted))
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
            Text("Nice run!")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
            Text("Let's take a look at how it went.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 32)
        .multilineTextAlignment(.center)
    }

    private var distancePacePage: some View {
        VStack(spacing: 36) {
            Text("Distance & pace")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)

            VStack(spacing: 2) {
                Text(distanceUnit.format(km: run.distanceKm))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("distance")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }

            HStack(spacing: 44) {
                miniStat(value: distanceUnit.formatPace(secPerKm: run.averagePaceSecPerKm), label: "avg pace")
                miniStat(value: durationText, label: "duration")
            }

            if run.effortType.isTempo || run.effortType.isInterval {
                Text(run.effortType.isTempo ? "Tempo run" : "Interval training")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }

    private func miniStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
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

    private var effortRatingPage: some View {
        VStack(spacing: 24) {
            Text("How did it feel?")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)

            Text("Tap the raccoon that matches this run")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            HStack(spacing: 20) {
                ForEach(PerceivedEffort.allCases) { effort in
                    effortOption(effort)
                }
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            selectedEffort = effortStore.effort(for: run.id)
        }
    }

    private func effortOption(_ effort: PerceivedEffort) -> some View {
        let isSelected = selectedEffort == effort

        return Button {
            selectedEffort = effort
            effortStore.setEffort(effort, for: run.id)
            // Klein natuurlijk momentje: na een keuze vanzelf doorschuiven naar de volgende
            // pagina, in plaats van dat de gebruiker ook nog los op "verder" moet tikken.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                goForward()
            }
        } label: {
            VStack(spacing: 10) {
                Mascot(pose: effort.pose, height: 56, tint: isSelected ? CozyPalette.level : .white)
                    .padding(14)
                    .background(isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? CozyPalette.level : .clear, lineWidth: 2)
                    )
                Text(effort.title)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(isSelected ? 1 : 0.7))
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var planComparisonPage: some View {
        if let comparison = relevantPlanComparison {
            ZStack {
                VStack(spacing: 28) {
                    Text("Compared to plan")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .textCase(.uppercase)

                    HStack(spacing: 8) {
                        Image(systemName: comparison.status == .onTarget ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        Text(comparison.status == .onTarget ? "On target" : "Off target")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.15))
                    .clipShape(Capsule())

                    planRow(
                        label: "Distance",
                        planned: distanceUnit.format(km: comparison.plannedRun.distanceKm, decimals: 1),
                        actual: distanceUnit.format(km: run.distanceKm, decimals: 1)
                    )
                    .padding(20)
                    .background(.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 32)

                    PaceRaceCard(
                        plannedPaceSecPerKm: comparison.plannedRun.targetPaceSecPerKm,
                        actualPaceSecPerKm: run.averagePaceSecPerKm,
                        distanceUnit: distanceUnit
                    )
                    .padding(.horizontal, 32)
                }

                // Alleen bij "op schema" of daadwerkelijk sneller dan gepland — een gemiste
                // of afwijkende run verdient geen feestelijke confetti erbovenop.
                if comparison.status == .onTarget || run.averagePaceSecPerKm < comparison.plannedRun.targetPaceSecPerKm {
                    RecapConfetti()
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func planRow(label: String, planned: String, actual: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(actual)
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text("planned \(planned)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var contributionPage: some View {
        VStack(spacing: 20) {
            Text("What this run gave you")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)

            VStack(spacing: 16) {
                contributionRow(icon: "flame.fill", label: "Stamina", before: contribution.staminaBefore, delta: contribution.staminaDelta)
                contributionRow(icon: "calendar", label: "Consistency", before: contribution.consistencyBefore, delta: contribution.consistencyDelta)
                contributionRow(icon: "bolt.fill", label: "Speed", before: contribution.speedBefore, delta: contribution.speedDelta)
            }
            .padding(.horizontal, 32)

            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.white)
                Text("+\(contribution.xpGained.formatted()) XP")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 4)
        }
    }

    private func contributionRow(icon: String, label: String, before: Int, delta: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label {
                    Text(label)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                } icon: {
                    Image(systemName: icon)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Text(delta > 0 ? "+\(delta)" : (delta < 0 ? "\(delta)" : "±0"))
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.15))
                    Capsule()
                        .fill(.white.opacity(0.9))
                        .frame(width: geo.size.width * CGFloat(barsFilled ? min(100, before + delta) : before) / 100)
                }
            }
            .frame(height: 8)
        }
    }

    @ViewBuilder
    private var raceReadinessPage: some View {
        if let raceGoal, let delta = raceReadinessDelta {
            VStack(spacing: 24) {
                Text("Race readiness")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .textCase(.uppercase)

                Text(raceGoal.title)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))

                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.15), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: CGFloat(barsFilled ? delta.after : delta.before) / 100)
                        .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text("\(barsFilled ? delta.after : delta.before)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("/ 100")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(width: 140, height: 140)
                .animation(.easeOut(duration: 1), value: barsFilled)

                let change = delta.after - delta.before
                Text(change > 0 ? "+\(change) points closer to race day" : "Every run keeps you on track")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    private var closingPage: some View {
        VStack(spacing: 20) {
            Mascot(pose: .reaching, height: 84, tint: .white)
            Text("Nice work!")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
            Text("Every run adds up. Keep it going.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Gefaseerde onthulling: eerst tekent de stippellijn zichzelf, dan verschijnt
            // de extra, op de streak gebaseerde aanmoediging, en pas daarna de knop — geeft
            // het slot een klein "moment" i.p.v. dat alles ineens tegelijk verschijnt.
            SquiggleLine()
                .trim(from: 0, to: closingLineDrawn ? 1 : 0)
                .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 10]))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 120, height: 20)
                .padding(.top, 4)

            if closingTextShown {
                Text(streakEncouragement)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if closingButtonShown {
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(backgroundColor(for: .closing))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(.horizontal, 32)
                .padding(.top, 12)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) {
                closingLineDrawn = true
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.75)) {
                closingTextShown = true
            }
            withAnimation(.easeOut(duration: 0.4).delay(1.25)) {
                closingButtonShown = true
            }
        }
    }

    /// Simpele, op de huidige streak gebaseerde aanmoediging — echte, betekenisvolle content
    /// i.p.v. kale opvultekst, aangezien de streak toch al overal in de app een centraal
    /// motiverend cijfer is (zie GameConstants.consistencyStreakScoreCurve).
    private var streakEncouragement: String {
        let streakWeeks = GameEngine.debugBreakdown(from: allRuns).streakWeeks
        if streakWeeks >= 2 {
            return "You're on a \(streakWeeks)-week streak. Keep showing up!"
        }
        return "Every run builds your streak. Keep showing up!"
    }
}

// MARK: - Previews met verzonnen data

/// Een paar weken aan nepgeschiedenis, zodat de stat-berekening (die naar recent volume/
/// streak kijkt) iets zinnigs heeft om een "voor"- en "na"-stand uit af te leiden — met maar
/// één losse run zou elke delta gewoon 0 zijn.
private func mockRunHistory(todayRun: RunWorkout) -> [RunWorkout] {
    let calendar = Calendar.current
    var runs: [RunWorkout] = [todayRun]
    for weeksAgo in 0..<4 {
        for dayOffset in [1, 3, 5] {
            guard let date = calendar.date(byAdding: .day, value: -(weeksAgo * 7 + dayOffset), to: Date()) else { continue }
            runs.append(RunWorkout(
                startDate: date,
                endDate: date.addingTimeInterval(1800),
                distanceMeters: 5200,
                durationSeconds: 1740
            ))
        }
    }
    return runs
}

#Preview("Met plan") {
    let today = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: Date()) ?? Date()
    let todayRun = RunWorkout(
        startDate: today,
        endDate: today.addingTimeInterval(1980),
        distanceMeters: 6100,
        durationSeconds: 1980,
        effortType: RunEffortType(isTempo: true, isInterval: false)
    )
    let plannedRun = PlannedRun(
        date: today,
        distanceKm: 6.0,
        targetPaceSecPerKm: 330,
        label: "Tempo run"
    )
    return RunRecapView(
        run: todayRun,
        allRuns: mockRunHistory(todayRun: todayRun),
        planComparison: plannedRun.comparison(against: mockRunHistory(todayRun: todayRun)),
        raceGoal: RaceGoal(distanceType: .half, customKm: 21.1, raceDate: Calendar.current.date(byAdding: .month, value: 2, to: Date()) ?? Date())
    )
}

#Preview("Zonder plan") {
    let today = Date()
    let todayRun = RunWorkout(
        startDate: today,
        endDate: today.addingTimeInterval(1500),
        distanceMeters: 4800,
        durationSeconds: 1500
    )
    return RunRecapView(
        run: todayRun,
        allRuns: mockRunHistory(todayRun: todayRun),
        planComparison: nil
    )
}

/// Simpele, licht golvende lijn — puur decoratief, om als "handgetekende stippellijn" te
/// animeren op het slotscherm. Geen poging tot een realistisch krabbeltje, gewoon een
/// zachte curve die met `trim(from:to:)` van links naar rechts kan "tekenen".
private struct SquiggleLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        path.move(to: CGPoint(x: 0, y: midY))
        path.addCurve(
            to: CGPoint(x: rect.width, y: midY),
            control1: CGPoint(x: rect.width * 0.3, y: rect.minY),
            control2: CGPoint(x: rect.width * 0.7, y: rect.maxY)
        )
        return path
    }
}

/// Twee baantjes met een bolletje dat racet op basis van tempo — sneller tempo = eerder bij
/// de finish. Een eigen, losse View (niet zomaar een functie) zodat elke keer dat je hierheen
/// terug-swipet een verse instantie ontstaat en de race opnieuw begint, in plaats van "al
/// aangekomen" te blijven staan van de vorige keer dat je deze pagina zag.
private struct PaceRaceCard: View {
    let plannedPaceSecPerKm: Double
    let actualPaceSecPerKm: Double
    let distanceUnit: DistanceUnit

    @State private var raceStarted = false

    /// Basis-duur voor het snelste tempo van de twee — de andere baan duurt evenredig langer,
    /// zodat het verschil in aankomsttijd echt het verschil in tempo weerspiegelt.
    private static let fastestLaneDuration = 1.8

    private var fasterPace: Double {
        min(plannedPaceSecPerKm, actualPaceSecPerKm)
    }

    private func duration(for pace: Double) -> Double {
        guard fasterPace > 0 else { return Self.fastestLaneDuration }
        return Self.fastestLaneDuration * (pace / fasterPace)
    }

    /// De baan met het snelste (laagste) tempo ligt het hele stuk voor — de volgorde wisselt
    /// nooit tijdens de animatie, aangezien beide lineair van start naar finish bewegen.
    private var actualIsFaster: Bool {
        actualPaceSecPerKm < plannedPaceSecPerKm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Pace race")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))

            lane(label: "You", pace: actualPaceSecPerKm, isYou: true)
            lane(label: "Plan", pace: plannedPaceSecPerKm, isYou: false)
        }
        .padding(20)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear {
            raceStarted = false
            // Piepklein uitstel zodat de bolletjes gegarandeerd eerst op de startlijn
            // getekend worden, vóórdat de animatie naar de finish in gang wordt gezet —
            // zonder dit zou de race soms al "halverwege" lijken te beginnen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                raceStarted = true
            }
        }
    }

    /// Groen als "You" sneller was dan het plan — anders (of voor de Plan-baan zelf) de
    /// gewone witte kleur, geen impliciet "fout"-rood voor een trager tempo.
    private func laneColor(isYou: Bool) -> Color {
        isYou && actualIsFaster ? CozyPalette.stamina : .white
    }

    private func lane(label: String, pace: Double, isYou: Bool) -> some View {
        let leading = isYou ? actualIsFaster : !actualIsFaster
        let color = laneColor(isYou: isYou)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(color.opacity(0.85))
                if leading {
                    Image(systemName: "arrow.forward.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(color)
                        .transition(.scale.combined(with: .opacity))
                }
                Spacer()
                Text(distanceUnit.formatPace(secPerKm: pace))
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.15))
                        .frame(height: 4)
                    // De vulling loopt gelijk op met het bolletje — zo zie je in één
                    // oogopslag welke baan al verder is, niet alleen wie als eerste finisht.
                    Capsule()
                        .fill(color.opacity(0.5))
                        .frame(width: raceStarted ? geo.size.width - 16 : 0, height: 4)
                        .animation(.easeInOut(duration: duration(for: pace)), value: raceStarted)
                    Circle()
                        .fill(color)
                        .frame(width: 16, height: 16)
                        .offset(x: raceStarted ? geo.size.width - 16 : 0)
                        .animation(.easeInOut(duration: duration(for: pace)), value: raceStarted)
                }
            }
            .frame(height: 16)
        }
    }
}

/// Kleine confetti-uitbarsting voor de "op schema/sneller"-viering — zelfde patroon als
/// ConfettiPiece in CelebrationView.swift, hier los gehouden zodat RunRecapView.swift niet
/// van dat bestand hoeft af te hangen voor iets simpels als losse stipjes.
private struct RecapConfetti: View {
    @State private var pieces: [Piece] = []
    @State private var animateOut = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { piece in
                    Circle()
                        .fill(piece.color)
                        .frame(width: piece.size, height: piece.size)
                        .position(
                            x: piece.xFraction * geo.size.width,
                            y: (animateOut ? piece.endYFraction : piece.startYFraction) * geo.size.height
                        )
                        .opacity(animateOut ? 0 : 1)
                        .animation(.easeOut(duration: 1.3).delay(piece.delay), value: animateOut)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            animateOut = false
            pieces = Piece.generate(count: 20)
            // 0,4 seconde i.p.v. een piepklein uitstel: de paginawissel zelf heeft een eigen
            // overgangsanimatie van 0,3 seconde (zie .transition op pageContent in body).
            // Start de confetti-animatie daar middenin, dan kan de impliciete animatie van
            // de paginawissel deze animatie verstoren of onzichtbaar "opslokken". Door ruim
            // ná die 0,3 seconde te beginnen, en expliciet withAnimation te gebruiken i.p.v.
            // te vertrouwen op het .animation(value:)-modifier alleen, staat deze animatie
            // gegarandeerd los van wat de paginawissel op dat moment nog aan het doen is.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                withAnimation(.easeOut(duration: 1.3)) {
                    animateOut = true
                }
            }
        }
    }

    private struct Piece: Identifiable {
        let id = UUID()
        let xFraction: CGFloat
        let startYFraction: CGFloat
        let endYFraction: CGFloat
        let size: CGFloat
        let color: Color
        let delay: Double

        static func generate(count: Int) -> [Piece] {
            let colors: [Color] = [CozyPalette.stamina, CozyPalette.speed, CozyPalette.level, .white]
            return (0..<count).map { _ in
                Piece(
                    xFraction: .random(in: 0.1...0.9),
                    startYFraction: .random(in: 0.25...0.4),
                    endYFraction: .random(in: 0.75...1.1),
                    size: .random(in: 5...10),
                    color: colors.randomElement() ?? .white,
                    delay: .random(in: 0...0.2)
                )
            }
        }
    }
}
