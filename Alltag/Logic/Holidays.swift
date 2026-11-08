import Foundation

/// Bundesländer für die gesetzlichen Feiertage.
enum Bundesland: String, CaseIterable, Identifiable {
    case bw = "BW", by = "BY", be = "BE", bb = "BB", hb = "HB", hh = "HH", he = "HE", mv = "MV"
    case ni = "NI", nw = "NW", rp = "RP", sl = "SL", sn = "SN", st = "ST", sh = "SH", th = "TH"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .bw: return "Baden-Württemberg"
        case .by: return "Bayern"
        case .be: return "Berlin"
        case .bb: return "Brandenburg"
        case .hb: return "Bremen"
        case .hh: return "Hamburg"
        case .he: return "Hessen"
        case .mv: return "Mecklenburg-Vorpommern"
        case .ni: return "Niedersachsen"
        case .nw: return "Nordrhein-Westfalen"
        case .rp: return "Rheinland-Pfalz"
        case .sl: return "Saarland"
        case .sn: return "Sachsen"
        case .st: return "Sachsen-Anhalt"
        case .sh: return "Schleswig-Holstein"
        case .th: return "Thüringen"
        }
    }

    static var sortedByName: [Bundesland] {
        allCases.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }
}

/// Gesetzliche Feiertage in Deutschland, berechnet für das eingestellte Bundesland.
/// Ohne Bundesland werden nur die bundesweiten Feiertage angezeigt.
enum Holidays {
    static let stateKey = "holiday.state"
    static let assumptionKey = "holiday.by.assumption"      // Mariä Himmelfahrt in Bayern
    static let corpusChristiKey = "holiday.regional.corpus" // Fronleichnam in Teilen von Sachsen/Thüringen

    struct Settings: Hashable {
        var state: Bundesland?
        var assumptionInBavaria: Bool
        var regionalCorpusChristi: Bool

        static func current() -> Settings {
            let d = UserDefaults.standard
            return Settings(state: Bundesland(rawValue: d.string(forKey: stateKey) ?? ""),
                            assumptionInBavaria: d.bool(forKey: assumptionKey),
                            regionalCorpusChristi: d.bool(forKey: corpusChristiKey))
        }
    }

    private struct CacheKey: Hashable {
        let year: Int
        let settings: Settings
    }

    private static var cache: [CacheKey: [DayKey: String]] = [:]
    private static let lock = NSLock()

    /// Name des Feiertags an diesem Tag (oder nil).
    static func name(on day: DayKey, settings: Settings = .current()) -> String? {
        let year = Day.components(day).year
        return holidays(year: year, settings: settings)[day]
    }

    static func holidays(year: Int, settings: Settings = .current()) -> [DayKey: String] {
        let key = CacheKey(year: year, settings: settings)
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let result = compute(year: year, settings: settings)
        cache[key] = result
        return result
    }

    /// Ostersonntag nach der Gaußschen Osterformel (gregorianisch).
    static func easter(_ year: Int) -> DayKey {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return Day.key(year: year, month: month, day: day)
    }

    private static func compute(year: Int, settings: Settings) -> [DayKey: String] {
        var result: [DayKey: String] = [:]
        let state = settings.state

        func add(_ day: DayKey, _ name: String, in states: Set<Bundesland>? = nil) {
            if let states {
                guard let state, states.contains(state) else { return }
            }
            result[day] = name
        }
        func fixed(_ month: Int, _ day: Int) -> DayKey { Day.key(year: year, month: month, day: day) }

        let easterSunday = Holidays.easter(year)

        add(fixed(1, 1), "Neujahr")
        add(fixed(1, 6), "Heilige Drei Könige", in: [.bw, .by, .st])

        var womensDay: Set<Bundesland> = []
        if year >= 2019 { womensDay.insert(.be) }
        if year >= 2023 { womensDay.insert(.mv) }
        add(fixed(3, 8), "Internationaler Frauentag", in: womensDay)

        add(Day.adding(-2, to: easterSunday), "Karfreitag")
        add(easterSunday, "Ostersonntag", in: [.bb])
        add(Day.adding(1, to: easterSunday), "Ostermontag")
        add(fixed(5, 1), "Tag der Arbeit")
        add(Day.adding(39, to: easterSunday), "Christi Himmelfahrt")
        add(Day.adding(49, to: easterSunday), "Pfingstsonntag", in: [.bb])
        add(Day.adding(50, to: easterSunday), "Pfingstmontag")

        var corpusChristi: Set<Bundesland> = [.bw, .by, .he, .nw, .rp, .sl]
        if settings.regionalCorpusChristi { corpusChristi.formUnion([.sn, .th]) }
        add(Day.adding(60, to: easterSunday), "Fronleichnam", in: corpusChristi)

        var assumption: Set<Bundesland> = [.sl]
        if settings.assumptionInBavaria { assumption.insert(.by) }
        add(fixed(8, 15), "Mariä Himmelfahrt", in: assumption)

        if year >= 2019 { add(fixed(9, 20), "Weltkindertag", in: [.th]) }
        add(fixed(10, 3), "Tag der Deutschen Einheit")

        var reformation: Set<Bundesland> = [.bb, .mv, .sn, .st, .th]
        if year >= 2018 { reformation.formUnion([.hb, .hh, .ni, .sh]) }
        add(fixed(10, 31), "Reformationstag", in: reformation)

        add(fixed(11, 1), "Allerheiligen", in: [.bw, .by, .nw, .rp, .sl])

        // Buß- und Bettag: Mittwoch vor dem 23. November
        var repentance = fixed(11, 22)
        while Day.weekday(repentance) != 4 { repentance = Day.adding(-1, to: repentance) }
        add(repentance, "Buß- und Bettag", in: [.sn])

        add(fixed(12, 25), "1. Weihnachtstag")
        add(fixed(12, 26), "2. Weihnachtstag")
        return result
    }

    /// Arbeitstage (Mo–Fr ohne Feiertage) in einem Zeitraum – z. B. für Urlaub.
    static func workdays(from start: DayKey, to end: DayKey, settings: Settings = .current()) -> Int {
        guard start <= end else { return 0 }
        var count = 0
        var day = start
        var steps = 0
        while day <= end && steps < 800 {
            let weekday = Day.weekday(day)
            if weekday != 1 && weekday != 7 && name(on: day, settings: settings) == nil {
                count += 1
            }
            day = Day.adding(1, to: day)
            steps += 1
        }
        return count
    }
}
