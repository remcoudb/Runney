import SwiftUI
import UIKit

// MARK: - Kleurenpalet

/// `nonisolated`: deze kleuren worden toegekend binnen BadgeDefinition/PlateauDetection's
/// nonisolated factory-methodes (bv. `color: CozyPalette.stamina`), die op hun beurt binnen
/// GameStatsStore's Task.detached draaien — zonder dit zouden die toekenningen niet compileren.
///
/// Elke kleur is dynamisch (via UIColor's trait-gebaseerde resolver): welke variant er
/// daadwerkelijk getoond wordt, hangt af van het systeem-uiterlijk (of de overrule-keuze in
/// Profiel, die via .preferredColorScheme op app-niveau wordt afgedwongen — zie RunneyApp.swift).
/// Bewust op déze manier (UIColor-closure) i.p.v. @Environment(\.colorScheme) overal waar een
/// kleur gebruikt wordt: zo hoeft geen van de honderden call sites door de hele app heen
/// aangepast te worden, dat blijft gewoon `CozyPalette.textPrimary` zoals het al was.
nonisolated enum CozyPalette {
    static let background = dynamicColor(light: (0.976, 0.965, 0.925), dark: (0.11, 0.10, 0.09))
    static let cardBackground = dynamicColor(light: (1, 1, 1), dark: (0.17, 0.16, 0.15))
    static let stamina = dynamicColor(light: (0.55, 0.78, 0.55), dark: (0.58, 0.80, 0.58))       // zacht groen
    static let consistency = dynamicColor(light: (0.55, 0.68, 0.90), dark: (0.62, 0.74, 0.94))   // zacht blauw
    static let speed = dynamicColor(light: (0.95, 0.70, 0.45), dark: (0.96, 0.73, 0.48))         // zacht oranje
    static let level = dynamicColor(light: (0.97, 0.82, 0.45), dark: (0.97, 0.84, 0.48))         // zacht geel
    static let textPrimary = dynamicColor(light: (0.17, 0.17, 0.16), dark: (0.94, 0.93, 0.90))
    static let textSecondary = dynamicColor(light: (0.53, 0.53, 0.50), dark: (0.68, 0.66, 0.62))

    /// Voor "vaste, solide" primaire actieknoppen (Verder, Klaar, Beginnen, etc.) — bewust
    /// altijd hoog contrast, ongeacht licht/donker: in licht is de knop donker met lichte
    /// tekst, in donker precies andersom. Zonder dit zou zo'n knop simpelweg
    /// `CozyPalette.textPrimary` als achtergrond gebruiken (die wél van kleur wisselt met
    /// het systeem), en in dark mode dus per ongeluk een lichte knop met nog steeds
    /// hardgecodeerd witte tekst opleveren — bijna onleesbaar.
    static let primaryButtonBackground = dynamicColor(light: (0.17, 0.17, 0.16), dark: (0.94, 0.93, 0.90))
    static let primaryButtonText = dynamicColor(light: (1, 1, 1), dark: (0.11, 0.10, 0.09))
}

/// Kleine helper zodat elke kleurdefinitie hierboven niet los een hele UIColor-closure hoeft
/// te herhalen — puur een lichte/donkere RGB-tupel meegeven volstaat.
/// `nonisolated`: wordt aangeroepen vanuit CozyPalette's static lets, die op hun beurt binnen
/// GameStatsStore's Task.detached gebruikt worden — een losse top-level functie zonder dit
/// zou anders alsnog default naar main-actor-isolatie vallen, zelfde valkuil als bij de
/// Int-extensie in GameEngine.swift.
private nonisolated func dynamicColor(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
    Color(uiColor: UIColor { traits in
        let (r, g, b) = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    })
}

// MARK: - Weergave (licht/donker/systeem, instelbaar via Profiel)

/// Sleutel voor de overrule-keuze — los van backgroundThemeStorageKey hieronder, want dit
/// gaat over licht/donker zelf, niet over welke kleur binnen dat licht/donker gebruikt wordt.
let appearanceOverrideStorageKey = "appearanceOverride"

enum AppearanceOverride: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    /// nil = laat SwiftUI gewoon het systeem volgen (geen overrule).
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var displayName: String {
        switch self {
        case .system: return String(localized: "System", comment: "Appearance option")
        case .light: return String(localized: "Light", comment: "Appearance option")
        case .dark: return String(localized: "Dark", comment: "Appearance option")
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

// MARK: - Achtergrondthema (instelbaar via Profiel)

/// De sleutel waaronder de gekozen achtergrondkleur staat opgeslagen — één centrale plek
/// zodat ProfileView en de cozyBackground()-modifier gegarandeerd dezelfde sleutel gebruiken.
let backgroundThemeStorageKey = "backgroundTheme"

enum BackgroundTheme: String, CaseIterable, Identifiable {
    case cream, mint, sky, lavender, blush

    var id: String { rawValue }

    /// Elke thema-kleur heeft ook een donkere variant — puur terugvallen op één universele
    /// donkere achtergrond zou de eigen gekozen kleur bij het omschakelen naar dark mode
    /// gewoon laten verdwijnen, terwijl dit juist een persoonlijke keuze hoort te blijven.
    var color: Color {
        switch self {
        case .cream: return CozyPalette.background
        case .mint: return dynamicColor(light: (0.90, 0.97, 0.92), dark: (0.09, 0.14, 0.11))
        case .sky: return dynamicColor(light: (0.90, 0.95, 0.99), dark: (0.08, 0.12, 0.17))
        case .lavender: return dynamicColor(light: (0.94, 0.91, 0.99), dark: (0.13, 0.11, 0.18))
        case .blush: return dynamicColor(light: (0.99, 0.91, 0.93), dark: (0.17, 0.10, 0.12))
        }
    }

    var displayName: String {
        switch self {
        case .cream: return String(localized: "Cream", comment: "Background theme option")
        case .mint: return String(localized: "Mint", comment: "Background theme option")
        case .sky: return String(localized: "Sky Blue", comment: "Background theme option")
        case .lavender: return String(localized: "Lavender", comment: "Background theme option")
        case .blush: return String(localized: "Blush", comment: "Background theme option")
        }
    }
}

// MARK: - Cozy card styling

/// Vlakke stijl (stap 1 van de stijlvernieuwing): kleinere radius, geen schaduw meer.
/// Voorheen 24pt radius + een zachte schaduw — dat gaf meer "papier op tafel"-diepte,
/// terwijl de referentiestijl juist vlakke, strak afgeronde witte kaarten gebruikt.
struct CozyCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(CozyPalette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Vult de achtergrond met de door de gebruiker gekozen kleur (Profiel), i.p.v. altijd de
/// vaste crème-kleur. Gecentraliseerd hier zodat elk scherm dezelfde @AppStorage-sleutel
/// hergebruikt in plaats van 'm los te herhalen. De kleur zelf is dynamisch (zie
/// BackgroundTheme.color hierboven), dus dark mode wordt hier automatisch meegenomen —
/// geen losse @Environment(\.colorScheme)-check nodig in deze modifier zelf.
private struct CozyBackground: ViewModifier {
    @AppStorage(backgroundThemeStorageKey) private var themeRaw: String = BackgroundTheme.cream.rawValue

    func body(content: Content) -> some View {
        content.background(
            (BackgroundTheme(rawValue: themeRaw) ?? .cream).color.ignoresSafeArea()
        )
    }
}

extension View {
    func cozyCard() -> some View {
        modifier(CozyCard())
    }

    func cozyBackground() -> some View {
        modifier(CozyBackground())
    }
}
