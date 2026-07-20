import SwiftUI

/// Welke gebeurtenis een viering triggert. Voeg hier nieuwe cases toe voor toekomstige
/// vieringen (bv. eerste tempoloop) — de UI zelf (CelebrationView) hoeft dan niet te veranderen.
enum CelebrationTrigger: Identifiable {
    case levelUp(GameStats)
    case streakMilestone(weeks: Int)
    case badge(BadgeDefinition)
    case personalRecord(PersonalRecord)

    var id: String {
        switch self {
        case .levelUp(let stats): return "level-\(stats.level)"
        case .streakMilestone(let weeks): return "streak-\(weeks)"
        case .badge(let definition): return "badge-\(definition.id)"
        // valueText meenemen zodat een opeenvolgende verbetering van hetzelfde record
        // (bv. twee keer achter elkaar een nieuw PR op de 5K) als een nieuw, uniek item
        // gezien wordt door fullScreenCover(item:) — anders zou de tweede viering niet
        // opnieuw getoond worden omdat het id ongewijzigd zou blijven.
        case .personalRecord(let record): return "record-\(record.id)-\(record.valueText(using: CelebrationTrigger.currentDistanceUnit))"
        }
    }

    var icon: String {
        switch self {
        case .levelUp: return "star.fill"
        case .streakMilestone: return "calendar"
        case .badge(let definition): return definition.icon
        case .personalRecord(let record): return record.icon
        }
    }

    var color: Color {
        switch self {
        case .levelUp: return CozyPalette.level
        case .streakMilestone: return CozyPalette.consistency
        case .badge(let definition): return definition.color
        case .personalRecord: return CozyPalette.speed
        }
    }

    var title: String {
        switch self {
        case .levelUp: return String(localized: "Level up!", comment: "Celebration title")
        case .streakMilestone: return String(localized: "Streak milestone!", comment: "Celebration title")
        case .badge: return String(localized: "Badge earned!", comment: "Celebration title")
        case .personalRecord: return String(localized: "New record!", comment: "Celebration title")
        }
    }

    var subtitle: String {
        switch self {
        case .levelUp(let stats): return "Level \(stats.level) — \(stats.levelTitle)"
        case .streakMilestone(let weeks):
            return weeks == 1
                ? String(localized: "1 week in a row", comment: "Celebration subtitle")
                : String(format: String(localized: "%d weeks in a row", comment: "Celebration subtitle"), weeks)
        case .badge(let definition): return definition.title
        case .personalRecord(let record): return "\(record.title): \(record.valueText(using: CelebrationTrigger.currentDistanceUnit))"
        }
    }

    /// CelebrationTrigger is een plain enum (geen View), dus geen @AppStorage-toegang —
    /// dit leest dezelfde UserDefaults-sleutel rechtstreeks, consistent met hoe @AppStorage
    /// 'm overal elders in de app benadert.
    private static var currentDistanceUnit: DistanceUnit {
        let raw = UserDefaults.standard.string(forKey: distanceUnitStorageKey) ?? DistanceUnit.kilometers.rawValue
        return DistanceUnit(rawValue: raw) ?? .kilometers
    }
}

/// Feestelijk full-screen scherm met een lichte confetti-animatie. Generiek: welke tekst/kleur/
/// icoon getoond wordt hangt volledig af van de meegegeven CelebrationTrigger.
struct CelebrationView: View {
    let trigger: CelebrationTrigger
    let onDismiss: () -> Void

    @State private var animateIn = false
    @State private var confetti: [ConfettiPiece] = []

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(confetti) { piece in
                    Circle()
                        .fill(piece.color)
                        .frame(width: piece.size, height: piece.size)
                        .position(
                            x: piece.xFraction * geo.size.width,
                            y: (animateIn ? piece.endYFraction : piece.startYFraction) * geo.size.height
                        )
                        .opacity(animateIn ? 0 : 1)
                        .animation(.easeOut(duration: 1.4).delay(piece.delay), value: animateIn)
                }
                .allowsHitTesting(false)

                VStack(spacing: 28) {
                    Spacer()

                    Mascot(pose: .reaching, height: 90)
                        .scaleEffect(animateIn ? 1 : 0.5)
                        .opacity(animateIn ? 1 : 0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.1), value: animateIn)

                    ZStack {
                        Circle()
                            .fill(trigger.color.opacity(0.25))
                            .frame(width: 140, height: 140)
                            .scaleEffect(animateIn ? 1 : 0.4)
                        Image(systemName: trigger.icon)
                            .font(.system(size: 56, weight: .bold))
                            .foregroundStyle(trigger.color)
                            .scaleEffect(animateIn ? 1 : 0.3)
                    }
                    .animation(.spring(response: 0.55, dampingFraction: 0.65), value: animateIn)

                    VStack(spacing: 8) {
                        Text(trigger.title)
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(CozyPalette.textPrimary)
                        Text(trigger.subtitle)
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .foregroundStyle(CozyPalette.textSecondary)
                    }
                    .multilineTextAlignment(.center)
                    .opacity(animateIn ? 1 : 0)
                    .animation(.easeOut(duration: 0.5).delay(0.15), value: animateIn)

                    Spacer()

                    Button(action: onDismiss) {
                        Text("Continue")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(CozyPalette.primaryButtonText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(CozyPalette.primaryButtonBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .opacity(animateIn ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.25), value: animateIn)
                }
                .padding(24)
            }
        }
        .cozyBackground()
        .onAppear {
            confetti = ConfettiPiece.generate(count: 24)
            animateIn = true
        }
    }
}

/// Eén losse confetti-stip. Posities zijn fracties (0...1) van het scherm, zodat dit
/// op elke schermgrootte klopt in plaats van vaste pixelwaarden te gebruiken.
private struct ConfettiPiece: Identifiable {
    let id = UUID()
    let xFraction: CGFloat
    let startYFraction: CGFloat
    let endYFraction: CGFloat
    let size: CGFloat
    let color: Color
    let delay: Double

    static func generate(count: Int) -> [ConfettiPiece] {
        let colors = [CozyPalette.stamina, CozyPalette.consistency, CozyPalette.speed, CozyPalette.level]
        return (0..<count).map { _ in
            ConfettiPiece(
                xFraction: .random(in: 0.05...0.95),
                startYFraction: .random(in: -0.08...0.05),
                endYFraction: .random(in: 0.65...1.05),
                size: .random(in: 6...12),
                color: colors.randomElement() ?? CozyPalette.level,
                delay: .random(in: 0...0.25)
            )
        }
    }
}

#Preview {
    CelebrationView(trigger: .streakMilestone(weeks: 4), onDismiss: {})
}
