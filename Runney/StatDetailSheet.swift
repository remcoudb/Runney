import SwiftUI

struct StatDetailSheet: View {
    let content: StatDetailContent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Text(content.description)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(CozyPalette.textPrimary)

                progressBar

                if !content.scoreBreakdown.isEmpty {
                    sectionTitle("How the score is built")
                    scoreBreakdownSection
                }

                sectionTitle("This week")
                VStack(spacing: 0) {
                    ForEach(Array(content.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Divider().opacity(0.5)
                        }
                        HStack {
                            Text(row.label)
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(CozyPalette.textPrimary)
                            Spacer()
                            Text(row.value)
                                .font(.system(.body, design: .rounded, weight: .semibold))
                                .foregroundStyle(CozyPalette.textSecondary)
                        }
                        .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 16)
                .background(CozyPalette.background)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                sectionTitle("How to improve this")
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(content.tips, id: \.self) { tip in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(content.color)
                                .padding(.top, 2)
                            Text(tip)
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(CozyPalette.textPrimary)
                        }
                    }
                }
                .padding(16)
                .background(CozyPalette.background)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                doneButton
            }
            .padding(20)
        }
        .background(CozyPalette.cardBackground.ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 10) {
                Image(systemName: content.icon)
                    .foregroundStyle(content.color)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 28, height: 28)
                Text(content.title)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(CozyPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
            Text(content.scoreText)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(content.color)
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(content.color.opacity(0.2))
                RoundedRectangle(cornerRadius: 8)
                    .fill(content.color)
                    .frame(width: geo.size.width * CGFloat(content.progress))
                    .animation(.easeOut(duration: 0.6), value: content.progress)

                if content.showsHundredScale {
                    ForEach([0.25, 0.5, 0.75], id: \.self) { fraction in
                        Rectangle()
                            .fill(Color.black.opacity(0.12))
                            .frame(width: 1)
                            .offset(x: geo.size.width * fraction)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(height: 14)
    }

    /// Toont elke ScoreCurveGroup als een eigen mini-tabel, met optionele subkop (bv.
    /// "Streak (max 60)") voor stats die uit meerdere onderdelen bestaan.
    private var scoreBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(content.scoreBreakdown) { group in
                VStack(alignment: .leading, spacing: 8) {
                    if let title = group.title {
                        Text(title)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(CozyPalette.textSecondary)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 {
                                Divider().opacity(0.5)
                            }
                            HStack {
                                Text(row.label)
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(CozyPalette.textPrimary)
                                Spacer()
                                Text(row.value)
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(content.color)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(CozyPalette.background)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Done")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(CozyPalette.primaryButtonText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(CozyPalette.primaryButtonBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.top, 8)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(CozyPalette.textPrimary)
    }
}

#Preview {
    StatDetailSheet(content: .stamina(breakdown: GameEngine.debugBreakdown(from: []), distanceUnit: .kilometers))
}
