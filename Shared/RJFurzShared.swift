import Foundation
import AppIntents

public enum RJFurzShared {
    public static let appGroup = "group.eu.rjuhas.furzapp.shared"
    public static let quickRecordURL = URL(string: "rjfurz://record")!

    public enum Period: String, CaseIterable, Codable {
        case day = "24h"
        case sevenDays = "7d"
        case thirtyDays = "30d"
        case currentWeek = "week"
        case all = "all"
    }

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    public static func writeCounts(day: Int, sevenDays: Int, thirtyDays: Int, currentWeek: Int, all: Int, score: Int) {
        let d = defaults
        d.set(day, forKey: "count.24h")
        d.set(sevenDays, forKey: "count.7d")
        d.set(thirtyDays, forKey: "count.30d")
        d.set(currentWeek, forKey: "count.week")
        d.set(all, forKey: "count.all")
        d.set(score, forKey: "score")
        d.set(Date().timeIntervalSince1970, forKey: "updated")
    }

    public static func count(for period: Period) -> Int {
        defaults.integer(forKey: "count.\(period.rawValue)")
    }

    public static var score: Int { defaults.integer(forKey: "score") }

    public static var defaultPeriod: Period {
        get { Period(rawValue: defaults.string(forKey: "widget.defaultPeriod") ?? "7d") ?? .sevenDays }
        set { defaults.set(newValue.rawValue, forKey: "widget.defaultPeriod") }
    }

    public static var updatedAt: Date? {
        let value = defaults.double(forKey: "updated")
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    public static func slogan(count: Int, score: Int) -> String {
        let pool: [String]
        if count == 0 {
            pool = quietSlogans
        } else if count <= 2 {
            pool = lightSlogans
        } else if count <= 6 {
            pool = activeSlogans
        } else if count <= 12 {
            pool = wildSlogans
        } else {
            pool = legendarySlogans
        }
        let seed = abs(count &* 37 &+ score &* 13 &+ Calendar.current.component(.day, from: .now))
        return pool[seed % pool.count]
    }

    // 100+ bewusst kurze, widget-taugliche Sprüche.
    private static let quietSlogans = [
        "Verdächtig still hier …", "Heute noch kein Lüftchen?", "Der Wind schläft noch.", "Furzradar meldet Ruhe.",
        "Noch alles druckfrei.", "Die Atmosphäre wartet.", "Stille vor dem Sturm?", "Kein Furz, kein Ruhm.",
        "Der Zähler döst noch.", "Heute sehr vornehm.", "Noch keine Wolke gesichtet.", "Die Hose schweigt.",
        "Windstärke null.", "Das Archiv wartet hungrig.", "Noch nichts zu vermelden.", "Luftreinhalteplan erfüllt.",
        "Ein ungewöhnlich ruhiger Tag.", "Der Furzdetektor gähnt.", "Heute noch kein Pfffft.", "Bereit, wenn du es bist."
    ]

    private static let lightSlogans = [
        "Ein solider Anfang 💨", "Kleines Lüftchen, großer Eintrag.", "Der erste ist dokumentiert!", "Ganz diskret abgegeben.",
        "Leise, aber historisch.", "Archiv offiziell eröffnet.", "Ein Pfffft für die Statistik.", "Das zählt! Wissenschaftlich fast.",
        "Sanfter Wind aus eigener Produktion.", "Ein kleiner Gruß an die Atmosphäre.", "Dezent, aber gespeichert.", "Furz Nummer eins steht.",
        "Der Tag nimmt Fahrt auf.", "Sauber protokolliert.", "Noch harmlos … noch.", "Ein Mini-Orkan im Archiv.",
        "Die Furzkarriere läuft an.", "Nicht schlecht für den Anfang.", "Ein Punkt fürs Luftkonto.", "Der Zähler lebt!"
    ]

    private static let activeSlogans = [
        "Heute läuft der Motor.", "Ordentliche Windproduktion!", "Du bist gut im Geschäft.", "Das Archiv wächst hörbar.",
        "Mehr Pfffft pro Stunde.", "Die Statistik wird würziger.", "Furzfrequenz: respektabel.", "Heute wird Geschichte geschrieben.",
        "Die Hose arbeitet Überstunden.", "Gute Ausbeute heute.", "Windpark RJ ist online.", "Das wird ein starker Tag.",
        "Schon wieder? Stark.", "Die Luft wird dünner.", "Produktivität auf Gasbasis.", "Dein Zähler hat Spaß.",
        "Solide Serie, weiter so.", "Die Atmosphäre kennt dich.", "Furzmodus eindeutig aktiv.", "Da kommt Rhythmus rein."
    ]

    private static let wildSlogans = [
        "Bitte Fenster prüfen 😂", "Windwarnung für Innenräume!", "Das Badezimmer hat Angst.", "Du meinst es heute ernst.",
        "Furzgewitter im Anmarsch.", "Der Zähler glüht.", "Lüften wäre jetzt sportlich.", "Heute volle Gasleistung.",
        "Die Nachbarschaft ahnt etwas.", "Atmosphäre erfolgreich verändert.", "EPA würde Fragen stellen.", "Dein Sofa hat genug gesehen.",
        "Das ist kein Wind, das ist Kunst.", "Furzkraftwerk auf Volllast.", "Die Luftqualität verhandelt.", "Ein sehr produktiver Hintertag.",
        "Dein Furz-Score macht Karriere.", "Geruchszone möglicherweise kritisch.", "Das Archiv braucht mehr Speicher.", "Die Wolkenbildung nimmt zu."
    ]

    private static let legendarySlogans = [
        "LEGENDÄR. Bitte evakuieren. 💨", "Du hast das Badezimmer vergast.", "Nationales Furzereignis.", "Der Wind gehört jetzt dir.",
        "Furz-CEO des Tages.", "Das ist statistisch unverschämt.", "Atmosphäre: besiegt.", "Heute keine halben Sachen.",
        "Der Zähler verlangt Urlaub.", "Furzniveau: Endgegner.", "Die Luft hat gekündigt.", "Du bist offiziell ein Windpark.",
        "Bitte den Raum neu zertifizieren.", "Furzrekordverdächtig!", "Das Archiv verneigt sich.", "Die Hose fordert Gefahrenzulage.",
        "Geruchswolke mit eigenem Klima.", "Heute bist du die Wetterlage.", "Unfassbare Gasbilanz.", "Der Furzthron gehört dir."
    ]
}


public enum QuickRecordRequest {
    public static let key = "quickRecord.requestedAt"

    public static func markRequested() {
        RJFurzShared.defaults.set(Date().timeIntervalSince1970, forKey: key)
    }

    public static func consumeIfRecent(maxAge: TimeInterval = 30) -> Bool {
        let value = RJFurzShared.defaults.double(forKey: key)
        guard value > 0 else { return false }
        RJFurzShared.defaults.removeObject(forKey: key)
        return Date().timeIntervalSince1970 - value <= maxAge
    }
}

public struct QuickFartRecordIntent: AppIntent {
    public static let title: LocalizedStringResource = "Furzaufnahme starten"
    public static let description = IntentDescription("Öffnet die RJ Furz-App sofort im Aufnahme-Modus.")
    public static var supportedModes: IntentModes { [.foreground(.immediate)] }

    public init() {}

    public func perform() async throws -> some IntentResult {
        QuickRecordRequest.markRequested()
        return .result()
    }
}
