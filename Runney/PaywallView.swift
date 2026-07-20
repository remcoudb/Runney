import SwiftUI
import StoreKit

/// Het betaalscherm. Wordt overal vandaan geopend waar een Pro-feature achter slot zit (zie
/// ProGateView) — presenteert zichzelf als sheet en sluit automatisch zodra de aankoop
/// (of restore) daadwerkelijk een geldig abonnement oplevert.
struct PaywallView: View {
    @ObservedObject private var subscriptions = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProduct: Product?
    @State private var isPurchasing = false
    @State private var isRestoring = false

    /// Vervang dit door de daadwerkelijke, live URL van je gehoste privacybeleid.
    private let privacyPolicyURL = URL(string: "https://remcoudb.github.io/Runney/")!
    /// Apple's standaard abonnementsvoorwaarden — gebruik dit tenzij je eigen, aangepaste
    /// Terms of Use hebt. Verplicht om te tonen bij elke paywall met een abonnement.
    private let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    featuresCard

                    if subscriptions.isLoadingProducts && subscriptions.products.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                    } else {
                        planPicker
                        purchaseButton
                        if let error = subscriptions.purchaseError {
                            Text(error)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(CozyPalette.speed)
                        }
                        footer
                    }
                }
                .padding(20)
            }
            .cozyBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await subscriptions.loadProducts()
                if selectedProduct == nil {
                    selectedProduct = subscriptions.yearlyProduct ?? subscriptions.products.first
                }
            }
            .onChange(of: subscriptions.isPro) { _, isPro in
                if isPro { dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Runney Pro")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(CozyPalette.textPrimary)
            Text("Unlock levels, badges, and everything that keeps you coming back.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var featuresCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            featureRow(icon: "star.fill", color: CozyPalette.level, title: "Levels & XP", text: "Climb through 20 levels as you run.")
            featureRow(icon: "rosette", color: CozyPalette.level, title: "Badges", text: "Unlock 40+ milestones along the way.")
            featureRow(icon: "trophy.fill", color: CozyPalette.speed, title: "Personal Records", text: "Track your all-time bests automatically.")
            featureRow(icon: "flag.checkered", color: CozyPalette.speed, title: "Race Readiness", text: "Know exactly how ready you are for race day.")
            featureRow(icon: "calendar.badge.clock", color: CozyPalette.consistency, title: "Planned Runs", text: "Follow your own training schedule, day by day.")
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(CozyPalette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Mascot(pose: .reaching, height: 50)
                .offset(x: -30, y: -45)
        }
    }

    private func featureRow(icon: String, color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 18, height: 18)
                    .aspectRatio(contentMode: .fit)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(CozyPalette.textPrimary)
                Text(text)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(CozyPalette.textSecondary)
            }
        }
    }

    private var planPicker: some View {
        VStack(spacing: 10) {
            ForEach(subscriptions.products) { product in
                planRow(product)
            }
        }
    }

    private func planRow(_ product: Product) -> some View {
        let isYearly = product.id == SubscriptionManager.ProductID.yearly.rawValue
        let isSelected = selectedProduct?.id == product.id

        return Button {
            selectedProduct = product
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(isYearly ? "Yearly" : "Monthly")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(CozyPalette.textPrimary)
                        if isYearly {
                            Text("Best value")
                                .font(.system(.caption2, design: .rounded, weight: .semibold))
                                .foregroundStyle(CozyPalette.level)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(CozyPalette.level.opacity(0.18))
                                .clipShape(Capsule())
                        }
                    }
                    Text(isYearly ? "7-day free trial, then \(product.displayPrice)/year" : "\(product.displayPrice)/month")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(CozyPalette.textSecondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? CozyPalette.stamina : CozyPalette.textSecondary.opacity(0.4))
            }
            .padding(16)
            .background(CozyPalette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? CozyPalette.stamina : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var purchaseButton: some View {
        Button {
            guard let selectedProduct else { return }
            isPurchasing = true
            Task {
                await subscriptions.purchase(selectedProduct)
                isPurchasing = false
            }
        } label: {
            if isPurchasing {
                ProgressView()
                    .tint(CozyPalette.primaryButtonText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                Text(purchaseButtonTitle)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(CozyPalette.primaryButtonText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
        }
        .background(CozyPalette.primaryButtonBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .disabled(selectedProduct == nil || isPurchasing)
    }

    private var purchaseButtonTitle: String {
        guard let selectedProduct else { return String(localized: "Continue", comment: "Paywall purchase button") }
        let isYearly = selectedProduct.id == SubscriptionManager.ProductID.yearly.rawValue
        return isYearly
            ? String(localized: "Start free trial", comment: "Paywall purchase button")
            : String(localized: "Unlock your full potential", comment: "Paywall purchase button")
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Button {
                isRestoring = true
                Task {
                    await subscriptions.restorePurchases()
                    isRestoring = false
                }
            } label: {
                if isRestoring {
                    ProgressView()
                } else {
                    Text("Restore Purchases")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(CozyPalette.textSecondary)
                }
            }

            HStack(spacing: 16) {
                Link("Terms of Use", destination: termsOfUseURL)
                Link("Privacy Policy", destination: privacyPolicyURL)
            }
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(CozyPalette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

#Preview {
    PaywallView()
}
