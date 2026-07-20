import SwiftUI

/// Het echte startpunt van de app. Toont de onboarding bij een verse installatie, en de
/// normale tab-navigatie zodra die doorlopen is (of overgeslagen bij de HealthKit-stap).
struct AppRootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    var body: some View {
        if hasCompletedOnboarding {
            RootTabView(onResetOnboarding: { hasCompletedOnboarding = false })
        } else {
            OnboardingView {
                hasCompletedOnboarding = true
            }
        }
    }
}

#Preview {
    AppRootView()
}
