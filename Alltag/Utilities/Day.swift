import Foundation

/// Ein Kalendertag als Schlüssel im Format "yyyy-MM-dd" (immer Europe/Berlin).
/// Strings lassen sich direkt vergleichen ("2026-11-06" < "2026-11-07") und sind
/// unempfindlich gegenüber Sommer-/Winterzeit-Umstellungen.
typealias DayKey = String

enum Day {
    static let timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
    static let locale = Locale(identifier: "de_DE")

    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.locale = locale
        cal.firstWeekday = 2          // Woche beginnt am Montag
        cal.minimumDaysInFirstWeek = 4
        return cal
    }()

    /// Reihenfolge der Wochentage für die Anzeige (Mo … So) als Calendar-Weekday (1 = So … 7 = Sa).
    static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    static var today: DayKey { key(for: Date()) }

    // MARK: - Umrechnung

    static func key(for date: Date) -> DayKey {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return key(year: c.year ?? 2000, month: c.month ?? 1, day: c.day ?? 1)
    }

    static func key(year: Int, month: Int, day: Int) -> DayKey {
        String(format: "%04ld-%02ld-%02ld", year, month, day)
    }

    static func components(_ key: DayKey) -> (year: Int, month: Int, day: Int) {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return (2000, 1, 1) }
        return (parts[0], parts[1], parts[2])
    }

    /// 12:00 Uhr an diesem Tag – sicher für Datumsrechnungen über Zeitumstellungen hinweg.
    static func noon(_ key: DayKey) -> Date {
        let c = components(key)
        return calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: 12)) ?? Date()
    }

    static func start(_ key: DayKey) -> Date {
        calendar.startOfDay(for: noon(key))
    }

    /// Konkreter Zeitpunkt an einem Tag (Minuten seit Mitternacht, Berliner Ortszeit).
    static func date(_ key: DayKey, minutes: Int) -> Date {
        let c = components(key)
        var dc = DateComponents(year: c.year, month: c.month, day: c.day, hour: minutes / 60, minute: minutes % 60)
        dc.second = 0
        return calendar.date(from: dc) ?? noon(key)
    }

    static func minutes(of date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func adding(_ days: Int, to key: DayKey) -> DayKey {
        let base = noon(key)
        let d = calendar.date(byAdding: .day, value: days, to: base) ?? base
        return self.key(for: d)
    }

    static func daysBetween(_ from: DayKey, _ to: DayKey) -> Int {
        calendar.dateComponents([.day], from: start(from), to: start(to)).day ?? 0
    }

    /// 1 = Sonntag … 7 = Samstag
    static func weekday(_ key: DayKey) -> Int {
        calendar.component(.weekday, from: noon(key))
    }

    // MARK: - Monate

    static func firstOfMonth(_ key: DayKey) -> DayKey {
        let c = components(key)
        return self.key(year: c.year, month: c.month, day: 1)
    }

    static func addingMonths(_ months: Int, to monthKey: DayKey) -> DayKey {
        let base = noon(firstOfMonth(monthKey))
        let d = calendar.date(byAdding: .month, value: months, to: base) ?? base
        return firstOfMonth(key(for: d))
    }

    static func daysInMonth(_ monthKey: DayKey) -> Int {
        calendar.range(of: .day, in: .month, for: noon(monthKey))?.count ?? 30
    }

    /// 42 Zellen (6 Wochen, Montag zuerst). `nil` = leere Zelle außerhalb des Monats.
    static func monthCells(_ monthKey: DayKey) -> [DayKey?] {
        let first = firstOfMonth(monthKey)
        let c = components(first)
        let leading = (weekday(first) + 5) % 7
        var cells: [DayKey?] = Array(repeating: nil, count: leading)
        for d in 1...daysInMonth(first) {
            cells.append(key(year: c.year, month: c.month, day: d))
        }
        while cells.count < 42 { cells.append(nil) }
        return cells
    }

    // MARK: - Formatierung

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = timeZone
        f.locale = locale
        f.dateFormat = format
        return f
    }

    private static let weekdayFormatter = formatter("EEEE")
    private static let longFormatter = formatter("d. MMMM yyyy")
    private static let fullFormatter = formatter("EEEE, d. MMMM")
    private static let mediumFormatter = formatter("EE, d. MMM yyyy")
    private static let shortFormatter = formatter("EE, d. MMM")
    private static let tinyFormatter = formatter("d.M.")
    private static let monthFormatter = formatter("MMMM")
    private static let yearFormatter = formatter("yyyy")

    /// "Heute", "Morgen", "Gestern" oder der Wochentag.
    static func relativeTitle(_ key: DayKey) -> String {
        let diff = daysBetween(today, key)
        if diff == 0 { return "Heute" }
        if diff == 1 { return "Morgen" }
        if diff == -1 { return "Gestern" }
        return weekdayFormatter.string(from: noon(key))
    }

    /// "heute", "gestern" oder "Fr., 6. Nov."
    static func relativeOrShort(_ key: DayKey) -> String {
        let diff = daysBetween(key, today)
        if diff == 0 { return "heute" }
        if diff == 1 { return "gestern" }
        return shortDate(key)
    }

    /// "6. November 2026"
    static func longDate(_ key: DayKey) -> String { longFormatter.string(from: noon(key)) }
    /// "Freitag, 6. November"
    static func fullDate(_ key: DayKey) -> String { fullFormatter.string(from: noon(key)) }
    /// "Fr., 6. Nov. 2026"
    static func mediumDate(_ key: DayKey) -> String { mediumFormatter.string(from: noon(key)) }
    /// "Fr., 6. Nov."
    static func shortDate(_ key: DayKey) -> String { shortFormatter.string(from: noon(key)) }
    /// "6.11."
    static func tinyDate(_ key: DayKey) -> String { tinyFormatter.string(from: noon(key)) }
    static func monthName(_ key: DayKey) -> String { monthFormatter.string(from: noon(key)) }
    static func yearString(_ key: DayKey) -> String { yearFormatter.string(from: noon(key)) }

    static func timeString(_ minutes: Int) -> String {
        String(format: "%02ld:%02ld", minutes / 60, minutes % 60)
    }

    static func shortWeekdayName(_ weekday: Int) -> String {
        let names = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
        return names[((weekday - 1) % 7 + 7) % 7]
    }
}

enum Fmt {
    private static let weightFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Day.locale
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f
    }()

    /// 80 → "80", 82.5 → "82,5"
    static func weight(_ value: Double) -> String {
        weightFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static let compactFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Day.locale
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = 0
        return f
    }()

    /// 12450 → "12.450"
    static func compact(_ value: Double) -> String {
        compactFormatter.string(from: NSNumber(value: value.rounded())) ?? String(Int(value))
    }

    /// Veränderung mit Vorzeichen: "+7,5" / "−2,5" / "±0"
    static func signed(_ value: Double, compact: Bool = false) -> String {
        let magnitude = abs(value)
        let text = compact ? Fmt.compact(magnitude) : weight(magnitude.rounded(toStep: 0.5))
        if magnitude < 0.05 { return "±0" }
        return (value > 0 ? "+" : "−") + text
    }

    static func parseDouble(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    static func parseInt(_ text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        if let i = Int(cleaned) { return i }
        if let d = parseDouble(cleaned) { return Int(d.rounded()) }
        return nil
    }

    static func todoCount(_ n: Int) -> String {
        n == 1 ? "1 To-Do" : "\(n) To-Dos"
    }

    static func habitCount(_ n: Int) -> String {
        n == 1 ? "1 Gewohnheit" : "\(n) Gewohnheiten"
    }

    static func appointmentCount(_ n: Int) -> String {
        n == 1 ? "1 Termin" : "\(n) Termine"
    }

    static func timeRange(_ start: Int?, _ end: Int?) -> String {
        guard let start else { return "ganztägig" }
        guard let end else { return Day.timeString(start) }
        return "\(Day.timeString(start))–\(Day.timeString(end))"
    }

    /// Erinnerungs-Vorlauf bei Terminen
    static let reminderOffsets = [0, 5, 15, 30, 60, 120, 1440]

    static func offsetLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "Zum Beginn"
        case 1440: return "1 Tag vorher"
        case let m where m % 60 == 0: return "\(m / 60) Std. vorher"
        default: return "\(minutes) Min. vorher"
        }
    }

    static func setText(_ set: SetValue) -> String {
        let w = set.weight.map { "\(weight($0)) kg" } ?? "–"
        let r = set.reps.map { String($0) } ?? "–"
        return "\(w) × \(r)"
    }
}

enum JSONBlob {
    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
