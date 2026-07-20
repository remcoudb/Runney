import Foundation
import StoreKit
import Combine

/// Beheert alles rond het Pro-abonnement: producten ophalen, aankopen, en bijhouden of de
/// gebruiker momenteel een geldig abonnement heeft. Eén centrale plek (net als GameStatsStore
/// voor de spelstatistieken) zodat elk scherm dat moet weten "is dit Pro?" hetzelfde,
/// live-bijgewerkte antwoord krijgt.
///
/// Product-ID's hieronder zijn voorstellen — je kunt ze vrij aanpassen, zolang ze exact
/// overeenkomen met wat je in App Store Connect aanmaakt (zie de losse instructies).
@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    enum ProductID: String, CaseIterable {
        case monthly = "com.runney.pro.monthly2"
        case yearly = "com.runney.pro.yearly"
    }

    /// Opgehaalde StoreKit-producten, prijs-oplopend gesorteerd (maandelijks eerst).
    @Published private(set) var products: [Product] = []
    #if DEBUG
    /// Zet dit tijdelijk op `false` als je juist het "geen Pro"-gedrag (sloten, paywall)
    /// wilt testen tijdens het ontwikkelen — staat standaard op `true` zodat je niet bij
    /// elke build opnieuw een testtransactie hoeft aan te maken.
    static let debugForcesPro = true
    #endif

    /// De bron van waarheid voor de rest van de app: heeft de gebruiker nu een geldig
    /// Pro-abonnement (inclusief actieve proefperiode)?
    /// In Debug-builds (dus alleen als je vanuit Xcode bouwt, nooit in TestFlight/App
    /// Store) volgt dit `debugForcesPro` hierboven i.p.v. de echte StoreKit-status.
    #if DEBUG
    @Published private(set) var isPro: Bool = debugForcesPro
    #else
    @Published private(set) var isPro: Bool = false
    #endif
    @Published private(set) var isLoadingProducts = false
    @Published var purchaseError: String?

    /// Blijft de hele levensduur van de app luisteren naar transactie-updates (bijv. een
    /// abonnement dat elders wordt afgesloten, of een uitgestelde aankoop die alsnog doorgaat).
    private var transactionListenerTask: Task<Void, Never>?

    private init() {
        transactionListenerTask = listenForTransactionUpdates()
        Task {
            await loadProducts()
            await refreshEntitlement()
        }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Producten laden

    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let fetched = try await Product.products(for: ProductID.allCases.map(\.rawValue))
            products = fetched.sorted { $0.price < $1.price }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    var monthlyProduct: Product? {
        products.first { $0.id == ProductID.monthly.rawValue }
    }

    var yearlyProduct: Product? {
        products.first { $0.id == ProductID.yearly.rawValue }
    }

    // MARK: - Aankopen

    func purchase(_ product: Product) async {
        purchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlement()
                }
                // .unverified: StoreKit kon de transactie niet valideren (bijv. geknoei) —
                // bewust NIET als geldig aanmerken, isPro blijft dan false.
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    /// Verplicht door Apple's richtlijnen: elke paywall moet een manier bieden om eerdere
    /// aankopen terug te zetten (bijv. na een herinstallatie of op een nieuw toestel).
    func restorePurchases() async {
        purchaseError = nil
        do {
            try await AppStore.sync()
            await refreshEntitlement()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Status bijhouden

    /// Loopt alle actieve rechten van de gebruiker langs (StoreKit's eigen, altijd-actuele
    /// bron van waarheid — geen eigen server nodig om dit bij te houden) en zet isPro op true
    /// zodra er een geldig, niet-ingetrokken abonnement bij zit.
    func refreshEntitlement() async {
        #if DEBUG
        // Zie debugForcesPro hierboven — zet die op false om de echte aankoopflow en
        // vergrendelde staat alsnog te kunnen testen tijdens het ontwikkelen.
        isPro = Self.debugForcesPro
        if Self.debugForcesPro { return }
        #endif
        var hasEntitlement = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               ProductID(rawValue: transaction.productID) != nil,
               transaction.revocationDate == nil {
                hasEntitlement = true
            }
        }
        isPro = hasEntitlement
    }

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refreshEntitlement()
            }
        }
    }
}
