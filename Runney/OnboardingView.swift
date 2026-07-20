import SwiftUI

private enum OnboardingStep: Int, CaseIterable {
    case welcome, name, mascotPreference, pillars, healthKit, pro
}

struct OnboardingView: View {
    let onComplete: () -> Void

    @AppStorage("userName") private var userName: String = ""
    @AppStorage(showsMascotStorageKey) private var showsMascot: Bool = true

    @State private var step: OnboardingStep = .welcome
    @State private var isConnecting = false
    @State private var showsPaywall = false

    var body: some View {
        VStack(spacing: 0) {
            progressDots
                .padding(.top, 20)

            Spacer()

            stepContent
                .padding(.horizontal, 28)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
                .id(step)

            Spacer()

            navigationButtons
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
        }
        .cozyBackground()
        .sheet(isPresented: $showsPaywall, onDismiss: onComplete) {
            PaywallView()
        }
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.self) { s in
                Circle()
                    .fill(s.rawValue <= step.rawValue ? CozyPalette.level : CozyPalette.level.opacity(0.25))
                    .frame(width: 8, height: 8)
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: welcomeStep
        case .name: nameStep
        case .mascotPreference: mascotPreferenceStep
        case .pillars: pillarsStep
        case .healthKit: healthKitStep
        case .pro: proStep
        }
    }

    // MARK: - Stappen

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Mascot(pose: .onboarding, height: 130)

            Text("Welcome to Runney")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(CozyPalette.textPrimary)
                .multilineTextAlignment(.center)

            Text("Running, but as a game. Build your stamina, consistency, and speed, level up, and collect badges along the way.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What should we call you?")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(CozyPalette.textPrimary)

            TextField("Name", text: $userName)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(CozyPalette.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(CozyPalette.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .autocorrectionDisabled()
                .submitLabel(.done)
                .overlay(alignment: .topTrailing) {
                    Mascot(pose: .greeting, height: 44, mirrored: true)
                        .offset(x: 6, y: -30)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mascotPreferenceStep: some View {
        VStack(spacing: 20) {
            Mascot(pose: .reaching, height: 90)

            Text("Meet your running buddy")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(CozyPalette.textPrimary)
                .multilineTextAlignment(.center)

            Text("A friendly raccoon shows up here and there — in celebrations, empty screens, and run recaps. You can always change this later in Profile.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)
                .multilineTextAlignment(.center)

            Toggle(isOn: $showsMascot) {
                Text("Show the raccoon")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(CozyPalette.textPrimary)
            }
            .tint(CozyPalette.stamina)
            .padding(16)
            .background(CozyPalette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }

    private var pillarsStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Four pillars, one goal")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(CozyPalette.textPrimary)

            pillarRow(icon: "flame.fill", color: CozyPalette.stamina, title: "Stamina", text: "Grows with your weekly kilometers.")
            pillarRow(icon: "calendar", color: CozyPalette.consistency, title: "Consistency", text: "Grows by running regularly, week after week.")
            pillarRow(icon: "bolt.fill", color: CozyPalette.speed, title: "Speed", text: "Grows with your pace and tempo runs.")
            pillarRow(icon: "star.fill", color: CozyPalette.level, title: "Level", text: "Grows permanently with every kilometer you run.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pillarRow(icon: String, color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(CozyPalette.textPrimary)
                Text(text)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(CozyPalette.textSecondary)
            }
        }
    }

    private var healthKitStep: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(CozyPalette.stamina.opacity(0.2))
                    .frame(width: 90, height: 90)
                if isConnecting {
                    ProgressView()
                } else {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(CozyPalette.stamina)
                }
            }

            Text("Connect to Apple Health")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(CozyPalette.textPrimary)
                .multilineTextAlignment(.center)

            Text("We read your running activities from Apple Health to calculate your progress. Your data stays on your device.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var proStep: some View {
        VStack(spacing: 20) {
            Mascot(pose: .reaching, height: 100)

            Text("Unlock the full experience")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(CozyPalette.textPrimary)
                .multilineTextAlignment(.center)

            Text("Levels, badges, personal records, and more — Runney Pro adds a whole extra layer on top of the free stats. Take a look, no pressure.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Navigatie

    private var navigationButtons: some View {
        VStack(spacing: 12) {
            Button(action: handlePrimaryAction) {
                Text(primaryButtonTitle)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(CozyPalette.primaryButtonText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(CozyPalette.primaryButtonBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .disabled(isConnecting)

            if step == .healthKit {
                Button("Set up later") {
                    withAnimation {
                        step = .pro
                    }
                }
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)
            } else if step == .pro {
                Button("Maybe later") {
                    onComplete()
                }
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)
            } else if step != .welcome {
                Button("Back") {
                    withAnimation {
                        step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome
                    }
                }
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(CozyPalette.textSecondary)
            }
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .welcome: return String(localized: "Get started", comment: "Onboarding primary button")
        case .name, .mascotPreference, .pillars: return String(localized: "Next", comment: "Onboarding primary button")
        case .healthKit: return String(localized: "Connect and start", comment: "Onboarding primary button")
        case .pro: return String(localized: "See Runney Pro", comment: "Onboarding primary button")
        }
    }

    private func handlePrimaryAction() {
        switch step {
        case .healthKit:
            isConnecting = true
            Task {
                await HealthKitManager.shared.setupAndFetch()
                isConnecting = false
                withAnimation {
                    step = .pro
                }
            }
        case .pro:
            showsPaywall = true
        default:
            withAnimation {
                step = OnboardingStep(rawValue: step.rawValue + 1) ?? .pro
            }
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
