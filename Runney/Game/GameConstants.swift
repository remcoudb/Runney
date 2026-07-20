import Foundation

/// Alle "magische getallen" van het gamification-systeem op één plek.
/// Pas deze aan om de moeilijkheidsgraad/balans te tunen zonder GameEngine te hoeven lezen.
/// `nonisolated`: dit zijn pure, onveranderlijke constanten — geen enkele reden om ze
/// (impliciet, via de project-brede "Default Actor Isolation"-instelling) main-actor-isolated
/// te maken. Zonder deze annotatie zijn ze niet leesbaar vanuit de nonisolated TaskGroup-taken
/// in HealthKitManager (parallelle effort-classificatie).
nonisolated enum GameConstants {

    // MARK: - Stamina
    /// Ankerpunten (km per week → score) voor de staffelschaal.
    /// Lineair geïnterpoleerd tussen punten; alles vanaf het laatste punt = 100.
    static let staminaScoreCurve: [(km: Double, score: Double)] = [
        (0, 0),
        (5, 15),
        (15, 40),
        (30, 70),
        (50, 100)
    ]
    /// Hoeveel weken terug we meewegen voor het "effectieve" weekvolume.
    /// Dit voorkomt dat één rustweek de score meteen laat instorten.
    static let staminaSmoothingWeeks: Int = 4
    /// Hoe sterk recentere weken meewegen t.o.v. oudere (0...1).
    /// Hoger = trager reagerend/stabieler, lager = reageert sneller op een rustweek.
    static let staminaDecayFactor: Double = 0.6

    // MARK: - Consistentie
    /// Minimum aantal trainingen per week om een week mee te laten tellen voor de streak.
    /// (Los van de week-check score hieronder, die naar aantal trainingen zelf kijkt.)
    static let consistencyStreakMinRunsPerWeek: Int = 1

    /// Week-check: score op basis van aantal trainingen déze week (max 40, discrete stappen).
    static let consistencyWeekCheckScores: [(runs: Int, score: Double)] = [
        (0, 0),
        (1, 15),
        (2, 30),
        (3, 40)
    ]

    /// Streak: score op basis van aantal opeenvolgende weken die aan het minimum voldoen (max 60).
    /// Lineair geïnterpoleerd tussen ankerpunten; 12+ weken = 60 (max).
    static let consistencyStreakScoreCurve: [(weeks: Double, score: Double)] = [
        (0, 0),
        (2, 10),
        (4, 25),
        (8, 45),
        (12, 60)
    ]

    /// Veiligheidslimiet zodat de streak-zoektocht niet oneindig doorzoekt.
    static let consistencyMaxStreakSearchWeeks: Int = 52

    // MARK: - Snelheid

    /// Pace Rating: ankerpunten (tempo in sec/km → score, max 60).
    /// Sneller tempo (lager sec/km) = hogere score. Sneller dan het snelste punt = 60 (cap),
    /// trager dan het traagste punt = 0. Het traagste ankerpunt (8:00/km) is een lineaire
    /// extrapolatie van de opgegeven schaal — pas aan als je een andere ondergrens wil.
    static let speedPaceRatingCurve: [(paceSecPerKm: Double, score: Double)] = [
        (255, 60),  // 4:15 /km
        (300, 45),  // 5:00 /km
        (360, 30),  // 6:00 /km
        (420, 15),  // 7:00 /km
        (480, 0)    // 8:00 /km (aanname: extrapolatie)
    ]
    /// Hoeveel dagen terug we zoeken naar de snelste run voor de Pace Rating.
    static let speedPaceLookbackDays: Int = 30
    /// Minimale afstand (km) om als "5km-poging" mee te tellen voor de Pace Rating.
    static let speedMinDistanceForPaceRatingKm: Double = 4.5

    /// Punten per workout-type bonus (tempoloop of intervaltraining), elk max 20 (samen max 40).
    static let speedBonusPointsPerType: Double = 20
    /// Hoeveel dagen de workout-type bonus actief blijft nadat hij geregistreerd is.
    static let speedBonusWindowDays: Int = 7

    /// Minimale duur (minuten) van een aaneengesloten snel segment om als tempoloop te tellen.
    static let tempoMinDurationMinutes: Double = 20
    /// Maximale variatiecoëfficiënt (stdev/gemiddelde) binnen een segment om nog als "gelijkmatig" te gelden.
    static let tempoMaxPaceVariance: Double = 0.08
    /// Minimale variatiecoëfficiënt over de hele run om als "wisselend tempo" (interval) te gelden.
    /// Bewust conservatief: normale variatie door heuvels/stoplichten/GPS-ruis zit doorgaans
    /// onder de 0,15-0,18. Pas omhoog als er nog te veel valse positieven zijn, omlaag als
    /// echte intervaltrainingen gemist worden.
    static let intervalMinPaceVariance: Double = 0.22
    /// Minimaal aantal pace-segmenten nodig om een betrouwbare interval-classificatie te maken.
    static let intervalMinSegmentCount: Int = 4
    /// Segmenten korter dan dit (seconden) worden genegeerd bij interval-detectie — te kort
    /// om een betrouwbare tempowaarde te geven, en dus een veelvoorkomende bron van valse positieven.
    static let intervalSegmentMinDurationSeconds: Double = 15
    /// Minimaal aantal segmenten dat duidelijk sneller dan gemiddeld moet zijn, om een
    /// herhaald patroon (echte intervallen) te onderscheiden van één toevallige uitschieter
    /// (bv. een sprintje voor een stoplicht).
    static let intervalMinFastSegments: Int = 3
    /// Hoeveel dagen terug we runs classificeren op tempoloop/interval (kost een extra query per run).
    static let effortClassificationLookbackDays: Int = 30

    // MARK: - XP & Level
    /// XP per kilometer. Simpele, vaste rate voor de POC.
    static let xpPerKm: Double = 100

    /// De 20 startlevels met naam en cumulatieve XP-drempel om dat level te bereiken.
    /// Let op: de sprong van level 12 → 13 (21.218 → 22.875 = +1.657) wijkt af van het
    /// patroon van de omliggende stappen (~+2.500-2.700). Mogelijk een typefout in de
    /// oorspronkelijke tabel (23.875 zou het patroon herstellen) — voorlopig letterlijk
    /// overgenomen zoals aangeleverd.
    /// `titleEN` is de brontaal-string (gebruikt in de code, en de sleutel in de
    /// vertaalcatalogus); `titleNL` is de vertaling die in Localizable.xcstrings komt te staan
    /// — voorheen andersom (Nederlands was de brontekst), nu omgewisseld voor de Engelstalige
    /// App Store-release. Beide namen bestonden al, alleen de rolverdeling is nu anders.
    static let levelThresholds: [(level: Int, xpRequired: Int, titleEN: String, titleNL: String)] = [
        (1, 0, "Couch Potato", "Couch Potato"),
        (2, 1_000, "Fast Walker", "Wandelaar met Haast"),
        (3, 2_297, "Pavement Jumper", "Stoeprand Springer"),
        (4, 3_815, "Jogger Recruit", "Jogger in Opleiding"),
        (5, 5_520, "Distance Apprentice", "Kilometer Vreter"),
        (6, 7_389, "Street Navigator", "Stratengids"),
        (7, 9_402, "Weather Seeker", "Weer- en Windbestendig"),
        (8, 11_545, "Hill Charger", "Heuvel Bestormer"),
        (9, 13_806, "Park Knight", "Parken Ridder"),
        (10, 16_177, "5K Vanguard", "De 5K Veteraan"),
        (11, 18_650, "Shadow Runner", "Schaduw Renner"),
        (12, 21_218, "Tarmac Shredder", "Asfalt Verscheurder"),
        (13, 22_875, "Cadence Keeper", "Cadans Bewaker"),
        (14, 26_618, "Pace Tamer", "Tempo Temmer"),
        (15, 29_444, "10K Commander", "De 10K Commandeur"),
        (16, 32_350, "Aero Dasher", "Windvanger"),
        (17, 35_334, "Unstoppable", "Onstuitbaar"),
        (18, 38_396, "Street Legend", "Straat Legende"),
        (19, 41_533, "Trail Blazer", "Trail Zoeker"),
        (20, 44_743, "Half Marathon Champion", "Halve Marathon Kampioen")
    ]

    // MARK: - Gedeeld
    /// Tempo (sec/km) dat als "beginnersniveau"/"makkelijk tempo" geldt. 7:00/km.
    /// Gebruikt door zowel XP-berekening als de tempoloop-classificatie.
    static let beginnerPaceSecPerKm: Double = 420
    /// Tempo (sec/km) dat als doel geldt. 4:00/km.
    static let goalPaceSecPerKm: Double = 240

    // MARK: - Racegereedheid
    /// Hoeveel procent van de wedstrijdafstand je langste training-run zou moeten zijn om op
    /// het maximum van dat onderdeel te zitten (raceReadinessLongestRunWeight punten).
    static let raceReadinessLongestRunFraction: Double = 0.82
    /// Hoeveel keer de wedstrijdafstand je effectieve weekvolume zou moeten zijn om op het
    /// maximum van dat onderdeel te zitten (raceReadinessWeeklyVolumeWeight punten).
    static let raceReadinessWeeklyVolumeMultiplier: Double = 1.7
    /// Hoeveel weken terug we kijken voor "langste training-run" en "weekvolume" — racegereedheid
    /// gaat over je huidige opbouw, niet je lifetime record.
    static let raceReadinessLookbackWeeks: Int = 8
    /// Afbouwfactor voor het gewogen weekvolume-gemiddelde binnen racegereedheid — losgekoppeld
    /// van Stamina's eigen staminaDecayFactor (0,6), want dat is getuned voor een kort venster
    /// (4 weken) waar snel reageren op de laatste tijd gewenst is. Racegereedheid kijkt over
    /// het volle raceReadinessLookbackWeeks-venster (8 weken) en wil dat ook grotendeels
    /// weerspiegelen, dus een zachtere afbouw: bij 0,6 zou week 7 nog maar ~3% wegen (bijna
    /// verwaarloosbaar), bij 0,85 nog ~32% — betekenisvol, maar recentere weken tellen nog
    /// steeds zwaarder.
    static let raceReadinessWeeklyVolumeDecayFactor: Double = 0.85
    /// Binnen dit aantal weken telt een longrun nog voor 100% mee (dekt de normale piek-
    /// timing van een trainingsschema: de langste run valt meestal een paar weken voor de
    /// wedstrijd, gevolgd door bewust afbouwen — dat mag dus niet worden afgestraft).
    /// Daarna neemt het gewicht lineair af tot raceReadinessLongestRunMinRecencyMultiplier
    /// aan het einde van het lookback-venster, zodat een eenmalige oude longrun die daarna
    /// nooit herhaald is niet blijvend een hoge score geeft.
    static let raceReadinessLongestRunPlateauWeeks: Int = 4
    /// Vloerwaarde (0...1) van de recency-weging aan het einde van het lookback-venster.
    static let raceReadinessLongestRunMinRecencyMultiplier: Double = 0.4
    /// Binnen dit aantal weken voor de wedstrijd schakelt het advies om naar "afbouwen"
    /// i.p.v. "nog opbouwen", ongeacht de score — een longrun proberen inhalen vlak voor de
    /// wedstrijd is juist riskant.
    static let raceReadinessTaperWeeks: Int = 3
    /// Binnen dit aantal dagen moet minstens één run gevallen zijn tijdens de taper, anders
    /// verschijnt een aanmoediging om licht te blijven bewegen — de score zelf blijft bevroren
    /// (zie de taper-logica in RaceReadiness.swift), maar "niks doen" is tijdens een taper
    /// óók niet de bedoeling, alleen "minder" — dat verschil raakt bewust alleen de
    /// begeleidende tekst, niet het cijfer.
    static let raceReadinessTaperActivityWindowDays: Int = 7

    /// Gewichten van de drie onderdelen — moeten optellen tot 100.
    static let raceReadinessLongestRunWeight: Double = 50
    static let raceReadinessWeeklyVolumeWeight: Double = 30
    static let raceReadinessConsistencyWeight: Double = 20

    // MARK: - Coach-inzichten
    /// Hoeveel weken terug we kijken om het XP-tempo te bepalen voor de level-voorspelling.
    static let levelForecastLookbackWeeks: Int = 4

    /// Hoeveel opeenvolgende (recente) weken een substat nauwelijks moet bewegen om als
    /// "plateau" te gelden.
    static let plateauDetectionWeeks: Int = 3
    /// Maximale bandbreedte (in scorepunten) binnen die weken om nog als "vlak" te gelden.
    static let plateauDetectionMaxVariance: Int = 5
    /// Minimale score om mee te tellen — voorkomt dat een substat die simpelweg nog nooit
    /// gestart is (bv. Snelheid op 0 omdat er nooit een tempoloop was) als "plateau" gezien
    /// wordt — dat is geen stilstand, dat is "nog niet begonnen".
    static let plateauDetectionMinValue: Int = 10
}
