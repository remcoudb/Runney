import SwiftUI

/// Centrale sleutel voor de aan/uit-instelling — één plek zodat elke Mascot-instantie
/// dezelfde @AppStorage-waarde leest. Zet iemand de mascotte uit in Profiel, dan verdwijnt
/// hij overal in de app tegelijk, zonder dat elke afzonderlijke plek dit los hoeft te checken.
let showsMascotStorageKey = "showsMascot"

/// Welke afbeelding bij welk moment hoort — de koppeling zelf gebeurt op de plek waar de
/// mascotte gebruikt wordt (HomeView, CelebrationView, etc.), dit is puur de asset-naam erachter.
enum MascotPose: String {
    /// Rustig zittend — het onboarding-welkomstscherm.
    case onboarding = "RaccoonMascot"
    /// Rustig zittend, andere houding — de Home-begroeting.
    case greeting = "RaccoonSitting"
    /// Rustig lopend — lege staten (nog geen runs, nog geen plan): er is nog niks gebeurd.
    case walking = "RaccoonWalking"
    /// Poten omhoog, kijkt omhoog — vieringen (level-up, badge, streak-mijlpaal).
    case reaching = "RaccoonReaching"
    /// In volle draf — actieve/dynamische momenten (bv. de terugblik op een run).
    case running = "RaccoonRunning"
    /// Middenin een sprong — alternatief voor running, net iets dynamischer.
    case leaping = "RaccoonLeaping"
}

/// Runney's mascotte-wasbeer, herbruikbaar op elke gewenste plek en in elke houding.
/// Respecteert automatisch de centrale aan/uit-instelling — als iemand die in Profiel
/// uitzet, geeft deze view simpelweg niets terug, overal waar hij gebruikt wordt.
struct Mascot: View {
    let pose: MascotPose
    var height: CGFloat = 60
    var mirrored: Bool = false
    /// Standaard de gewone tekstkleur, maar overschrijfbaar voor contexten met een donkere
    /// achtergrond (zoals RunRecapView) waar de mascotte anders onzichtbaar zou zijn.
    var tint: Color = CozyPalette.textPrimary

    @AppStorage(showsMascotStorageKey) private var showsMascot: Bool = true

    var body: some View {
        if showsMascot {
            Image(pose.rawValue)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: height)
                .foregroundStyle(tint)
                .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                .allowsHitTesting(false)
        }
    }
}
