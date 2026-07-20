import SwiftUI

/// Runney's mascotte: een wasbeer, volledig getekend met SwiftUI-vormen (cirkels, ellipsen,
/// capsules) — geen los afbeeldingsbestand nodig, dus geen extra asset om te beheren, en
/// scherp op elke schermgrootte/resolutie. `size` is de breedte van de kop zelf; het geheel
/// (incl. oren en optionele staart) neemt iets meer ruimte in.
struct RaccoonMascot: View {
    var size: CGFloat = 120
    /// Staart alleen tonen bij een groter formaat (bijv. het onboarding-welkomstscherm) —
    /// bij kleine formaten (lege-staat-icoontjes) voegt die vooral ruis toe.
    var showsTail: Bool = false

    private var bodyColor: Color { Color(red: 0.64, green: 0.60, blue: 0.57) }
    private var darkColor: Color { Color(red: 0.28, green: 0.25, blue: 0.24) }
    private var faceColor: Color { Color(red: 0.94, green: 0.92, blue: 0.89) }
    private var noseColor: Color { Color(red: 0.22, green: 0.19, blue: 0.18) }

    var body: some View {
        ZStack {
            if showsTail {
                tail
            }

            // Oren: donkere buitenkant + lichter binnenkant, iets achter en boven de kop.
            HStack(spacing: size * 0.5) {
                ear
                ear
            }
            .offset(y: -size * 0.42)

            // Kop.
            Circle()
                .fill(faceColor)
                .frame(width: size, height: size)

            // Het typische bandietenmasker over de ogen.
            Capsule()
                .fill(darkColor)
                .frame(width: size * 0.86, height: size * 0.3)
                .offset(y: -size * 0.04)

            // Ogen, boven op het masker.
            HStack(spacing: size * 0.24) {
                eye
                eye
            }
            .offset(y: -size * 0.06)

            // Snoetje: iets lichter ovaal onderaan de kop, met de neus erop.
            Ellipse()
                .fill(bodyColor.opacity(0.35))
                .frame(width: size * 0.42, height: size * 0.3)
                .offset(y: size * 0.22)

            Ellipse()
                .fill(noseColor)
                .frame(width: size * 0.16, height: size * 0.12)
                .offset(y: size * 0.16)
        }
        .frame(width: size * 1.3, height: size * 1.3)
    }

    private var ear: some View {
        ZStack {
            Circle()
                .fill(darkColor)
                .frame(width: size * 0.32, height: size * 0.32)
            Circle()
                .fill(bodyColor)
                .frame(width: size * 0.18, height: size * 0.18)
        }
    }

    private var eye: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: size * 0.17, height: size * 0.17)
            Circle()
                .fill(darkColor)
                .frame(width: size * 0.09, height: size * 0.09)
        }
    }

    /// Geringde staart — de andere herkenbare wasbeer-trek, alleen bij `showsTail: true`.
    private var tail: some View {
        VStack(spacing: size * 0.02) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(index % 2 == 0 ? bodyColor : darkColor)
                    .frame(width: size * 0.34, height: size * 0.16)
            }
        }
        .rotationEffect(.degrees(28))
        .offset(x: size * 0.62, y: size * 0.5)
    }
}

#Preview {
    VStack(spacing: 40) {
        RaccoonMascot(size: 140, showsTail: true)
        RaccoonMascot(size: 48)
    }
    .padding(40)
    .background(CozyPalette.background)
}
