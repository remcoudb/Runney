import Foundation

/// Encodeert/decodeert geplande runs naar een deelbare `runney://`-link. Bewust geen server:
/// de data zelf zit gecodeerd in de link (base64-JSON), dus delen werkt via elk kanaal dat
/// een link kan versturen — Berichten, WhatsApp, AirDrop, Mail, wat dan ook. Past zo bij de
/// "alles blijft lokaal"-aanpak van de rest van de app.
enum PlannedRunSharing {
    private static let scheme = "runney"
    private static let host = "import-plan"
    private static let queryItemName = "data"

    /// Bouwt een deelbare link met de meegegeven geplande runs erin gecodeerd. Nil als
    /// encoderen om wat voor reden dan ook mislukt (zou in de praktijk niet moeten gebeuren
    /// voor een simpele Codable-struct als PlannedRun).
    static func shareURL(for plannedRuns: [PlannedRun]) -> URL? {
        guard let jsonData = try? JSONEncoder().encode(plannedRuns) else { return nil }
        let base64 = jsonData.base64EncodedString()

        // Via URLComponents opgebouwd i.p.v. string-interpolatie, zodat de base64-waarde
        // (die +, / en = kan bevatten) automatisch correct percent-encoded wordt.
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: queryItemName, value: base64)]
        return components.url
    }

    /// Een vriendelijke, leesbare tekst met de link erin verweven — bedoeld om te delen
    /// i.p.v. de kale URL zelf. Een `runney://`-link krijgt namelijk nooit een mooie
    /// voorvertoning in Berichten/WhatsApp (dat werkt alleen bij gewone https-links), dus
    /// zonder omkadering zou de ontvanger alleen een technisch ogende, onleesbare regel
    /// tekst zien in plaats van iets wat uitnodigt om te tikken.
    /// Puur de begeleidende tekst, zonder de link erin verweven — die gaat apart mee als het
    /// eigenlijke deelitem (zie ShareLink in PlannedRunsView.swift). Een `runney://`-link
    /// wordt namelijk alleen betrouwbaar herkend en geopend als 'm als een écht URL-object
    /// gedeeld wordt; verweven in gewone tekst herkennen de meeste berichten-apps een eigen
    /// (niet-https) linkschema niet automatisch als klikbare link, waardoor 'm bij de
    /// ontvanger gewoon als kale, niet-werkende tekst blijft staan.
    static func shareIntroText(for plannedRuns: [PlannedRun]) -> String {
        let intro = plannedRuns.count == 1
            ? String(localized: "I planned a run for you in Runney!", comment: "Share message intro, singular")
            : String(localized: "I planned some runs for you in Runney!", comment: "Share message intro, plural")
        let instruction = String(localized: "Open this link on your phone to add it to your schedule.", comment: "Share message instruction")
        return "\(intro) \(instruction)"
    }

    /// Decodeert een binnengekomen `runney://`-link terug naar geplande runs, of nil als de
    /// link niet van dit type is of niet te decoderen valt (bijv. corrupt gekopieerd, of een
    /// link van een oudere/nieuwere appversie met een incompatibel formaat).
    static func plannedRuns(from url: URL) -> [PlannedRun]? {
        guard url.scheme == scheme, url.host == host else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let base64 = components.queryItems?.first(where: { $0.name == queryItemName })?.value,
              let jsonData = Data(base64Encoded: base64),
              let plannedRuns = try? JSONDecoder().decode([PlannedRun].self, from: jsonData)
        else { return nil }
        return plannedRuns
    }
}
