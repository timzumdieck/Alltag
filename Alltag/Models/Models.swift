import Foundation
import SwiftData

// MARK: - Hilfsstrukturen (als JSON in den Modellen gespeichert)

/// Eine Übung innerhalb einer Trainingseinheit.
struct PlanEntry: Codable, Hashable, Identifiable {
    var id: UUID
    var exerciseID: UUID
    var sets: Int

    init(id: UUID = UUID(), exerciseID: UUID, sets: Int) {
        self.id = id
        self.exerciseID = exerciseID
        self.sets = sets
    }
}

/// Wiederkehrende Wochentage, gültig ab einem Tag.
/// Bei Änderungen wird eine neue Regel ab heute angehängt – vergangene Tage bleiben unverändert.
struct ScheduleRule: Codable, Hashable {
    var validFrom: DayKey
    var weekdays: [Int]
}

/// Trainingszeitraum: an bestimmten Wochentagen von … bis (jeweils einschließlich).
/// Ohne Enddatum gilt er ab dem Starttag dauerhaft.
struct SchedulePeriod: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var start: DayKey
    var end: DayKey?
    var weekdays: [Int]

    func contains(_ day: DayKey) -> Bool {
        day >= start && (end.map { day <= $0 } ?? true)
    }

    func occurs(on day: DayKey) -> Bool {
        contains(day) && weekdays.contains(Day.weekday(day))
    }

    /// Endet der Zeitraum vor diesem Tag?
    func isOver(at day: DayKey) -> Bool {
        end.map { $0 < day } ?? false
    }

    var weekdayText: String {
        let names = Day.weekdayOrder.filter { weekdays.contains($0) }.map { Day.shortWeekdayName($0) }
        return names.isEmpty ? "Keine Wochentage" : names.joined(separator: ", ")
    }

    var rangeText: String {
        guard let end else { return "ab \(Day.mediumDate(start))" }
        return "\(Day.shortDate(start)) – \(Day.mediumDate(end))"
    }
}

/// Ein Satz: Gewicht in kg und Wiederholungen.
struct SetValue: Codable, Hashable {
    var weight: Double?
    var reps: Int?

    init(weight: Double? = nil, reps: Int? = nil) {
        self.weight = weight
        self.reps = reps
    }

    var isEmpty: Bool { weight == nil && reps == nil }
}

/// Eine Übung innerhalb eines durchgeführten Trainings.
struct SessionExercise: Codable, Hashable {
    var exerciseID: UUID
    var name: String
    var sets: [SetValue]
}

enum RepeatKind: String, Codable, CaseIterable, Identifiable {
    case once, daily, weekdays, monthly, dates

    var id: String { rawValue }

    var label: String {
        switch self {
        case .once: return "Einmalig"
        case .daily: return "Täglich"
        case .weekdays: return "Wöchentlich"
        case .monthly: return "Monatlich"
        case .dates: return "Genaue Daten"
        }
    }

    /// Unterstützt „alle X Tage/Wochen/Monate“
    var hasInterval: Bool {
        self == .daily || self == .weekdays || self == .monthly
    }

    func intervalLabel(_ n: Int) -> String {
        switch self {
        case .daily: return n == 1 ? "Jeden Tag" : "Alle \(n) Tage"
        case .weekdays: return n == 1 ? "Jede Woche" : "Alle \(n) Wochen"
        case .monthly: return n == 1 ? "Jeden Monat" : "Alle \(n) Monate"
        case .once, .dates: return ""
        }
    }

    var maxInterval: Int {
        self == .monthly ? 12 : 6
    }
}

/// Monatliche Wiederholung: am gleichen Tag (z. B. am 15.), am n-ten Wochentag (z. B. 2. Mittwoch)
/// oder am letzten Wochentag des Monats.
enum MonthlyMode: String, Codable, CaseIterable {
    case dayOfMonth, weekdayOrdinal, lastWeekday
}

/// Art eines Eintrags im To-Do-Tab.
enum EntryKind: String, Codable, CaseIterable, Identifiable {
    case todo, appointment, habit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .todo: return "To-Do"
        case .appointment: return "Termin"
        case .habit: return "Gewohnheit"
        }
    }

    var sectionTitle: String {
        switch self {
        case .todo: return "To-Dos"
        case .appointment: return "Termine"
        case .habit: return "Gewohnheiten"
        }
    }

    var symbol: String {
        switch self {
        case .todo: return "checklist"
        case .appointment: return "calendar"
        case .habit: return "leaf"
        }
    }
}

// MARK: - SwiftData-Modelle

@Model
final class Exercise {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()

    init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

@Model
final class WorkoutPlan {
    var id: UUID = UUID()
    var name: String = ""
    var entriesData: Data = Data()
    var rulesData: Data = Data()
    var specificDays: [String] = []
    /// Tage, an denen diese Einheit ausnahmsweise entfällt.
    var skippedDays: [String] = []
    /// Zeiträume mit eigenen Wochentagen (z. B. 1.1.–1.3. montags)
    var periodsData: Data = Data()
    var createdAt: Date = Date()

    init(id: UUID = UUID(),
         name: String,
         entries: [PlanEntry] = [],
         rules: [ScheduleRule] = [],
         specificDays: [String] = [],
         skippedDays: [String] = [],
         periods: [SchedulePeriod] = [],
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.entriesData = JSONBlob.encode(entries)
        self.rulesData = JSONBlob.encode(rules)
        self.specificDays = specificDays
        self.skippedDays = skippedDays
        self.periodsData = JSONBlob.encode(periods)
        self.createdAt = createdAt
    }

    var periods: [SchedulePeriod] {
        get { JSONBlob.decode([SchedulePeriod].self, from: periodsData) ?? [] }
        set { periodsData = JSONBlob.encode(newValue) }
    }

    var entries: [PlanEntry] {
        get { JSONBlob.decode([PlanEntry].self, from: entriesData) ?? [] }
        set { entriesData = JSONBlob.encode(newValue) }
    }

    var rules: [ScheduleRule] {
        get { JSONBlob.decode([ScheduleRule].self, from: rulesData) ?? [] }
        set { rulesData = JSONBlob.encode(newValue) }
    }

    /// Die aktuell gültigen Wochentage (neueste Regel).
    var currentWeekdays: [Int] {
        rules.sorted { $0.validFrom < $1.validFrom }.last?.weekdays ?? []
    }

    var scheduleSummary: String {
        let current = currentWeekdays
        let names = Day.weekdayOrder.filter { current.contains($0) }.map { Day.shortWeekdayName($0) }
        let today = Day.today
        let upcoming = specificDays.filter { $0 >= today }.count
        var parts: [String] = []
        if !names.isEmpty { parts.append(names.joined(separator: ", ")) }
        for period in periods.sorted(by: { $0.start < $1.start }) where !period.isOver(at: today) {
            parts.append("\(period.weekdayText) \(period.rangeText)")
        }
        if upcoming > 0 { parts.append(upcoming == 1 ? "1 weiterer Termin" : "\(upcoming) weitere Termine") }
        return parts.isEmpty ? "Keine Trainingstage" : parts.joined(separator: " · ")
    }
}

@Model
final class WorkoutSession {
    var id: UUID = UUID()
    var day: String = ""
    var planID: UUID?
    var planName: String = ""
    var exercisesData: Data = Data()
    var isCompleted: Bool = false
    var completedAt: Date?
    var updatedAt: Date = Date()

    init(id: UUID = UUID(),
         day: DayKey,
         planID: UUID?,
         planName: String,
         exercises: [SessionExercise] = [],
         isCompleted: Bool = false,
         completedAt: Date? = nil,
         updatedAt: Date = Date()) {
        self.id = id
        self.day = day
        self.planID = planID
        self.planName = planName
        self.exercisesData = JSONBlob.encode(exercises)
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.updatedAt = updatedAt
    }

    var exercises: [SessionExercise] {
        get { JSONBlob.decode([SessionExercise].self, from: exercisesData) ?? [] }
        set { exercisesData = JSONBlob.encode(newValue) }
    }

    var hasData: Bool {
        exercises.contains { ex in ex.sets.contains { !$0.isEmpty } }
    }
}

@Model
final class TodoItem {
    var id: UUID = UUID()
    var title: String = ""
    var startDay: String = ""
    var endDay: String?
    var timeMinutes: Int?
    var repeatRaw: String = "once"
    var weekdays: [Int] = []
    var dates: [String] = []
    var exceptions: [String] = []
    var reminderMinutes: Int?
    var carryOver: Bool = false
    var createdAt: Date = Date()
    /// To-Do, Termin oder Gewohnheit
    var kindRaw: String = "todo"
    /// Ende eines Termins (Minuten seit Mitternacht)
    var endMinutes: Int?
    /// Erinnerung bei Terminen: Minuten vor Beginn
    var reminderOffset: Int?
    /// Ort eines Termins
    var location: String = ""

    init(id: UUID = UUID(), title: String = "", startDay: DayKey = Day.today, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.startDay = startDay
        self.createdAt = createdAt
    }

    var repeatKind: RepeatKind {
        get { RepeatKind(rawValue: repeatRaw) ?? .once }
        set { repeatRaw = newValue.rawValue }
    }

    /// Alle X Tage/Wochen/Monate (1 = jedes Mal)
    var repeatInterval: Int = 1
    var monthlyModeRaw: String = "dayOfMonth"
    /// Tag im Monat bei „am gleichen Tag“ (1–31; in kürzeren Monaten der Monatsletzte)
    var monthlyDay: Int = 0

    var monthlyMode: MonthlyMode {
        get { MonthlyMode(rawValue: monthlyModeRaw) ?? .dayOfMonth }
        set { monthlyModeRaw = newValue.rawValue }
    }

    var isRecurring: Bool { repeatKind != .once }

    var entryKind: EntryKind {
        get { EntryKind(rawValue: kindRaw) ?? .todo }
        set { kindRaw = newValue.rawValue }
    }

    /// „Auf den nächsten Tag verschieben“ gilt für To-Dos und Gewohnheiten (nicht für Termine).
    var carries: Bool { carryOver && entryKind != .appointment }

    /// Einmaliger Eintrag über mehrere Tage (Enddatum nach dem Startdatum):
    /// Termin = mehrtägig, To-Do = Zeitraum, in dem es erledigt werden soll.
    var isSpan: Bool {
        guard repeatKind == .once, let end = endDay else { return false }
        return end > startDay
    }
}

/// Urlaub von … bis (jeweils einschließlich).
@Model
final class Vacation {
    var id: UUID = UUID()
    var title: String = ""
    var startDay: String = ""
    var endDay: String = ""
    /// Geplante Trainings fallen in dieser Zeit aus.
    var pausesTraining: Bool = false
    var createdAt: Date = Date()

    init(id: UUID = UUID(),
         title: String,
         startDay: DayKey,
         endDay: DayKey,
         pausesTraining: Bool = false,
         createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.startDay = startDay
        self.endDay = endDay
        self.pausesTraining = pausesTraining
        self.createdAt = createdAt
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Urlaub" : trimmed
    }

    func contains(_ day: DayKey) -> Bool {
        day >= startDay && day <= endDay
    }
}

/// Erledigt-Status eines einzelnen Vorkommens eines To-Dos.
@Model
final class TodoCompletion {
    var id: UUID = UUID()
    var todoID: UUID = UUID()
    /// Tag, für den das To-Do ursprünglich geplant war.
    var day: String = ""
    /// Tag, an dem es abgehakt wurde (relevant für „auf den nächsten Tag verschieben“).
    var doneDay: String = ""
    var completedAt: Date = Date()

    init(id: UUID = UUID(), todoID: UUID, day: DayKey, doneDay: DayKey, completedAt: Date = Date()) {
        self.id = id
        self.todoID = todoID
        self.day = day
        self.doneDay = doneDay
        self.completedAt = completedAt
    }
}

// MARK: - Container

enum Persistence {
    static let container: ModelContainer = {
        let schema = Schema([
            Exercise.self,
            WorkoutPlan.self,
            WorkoutSession.self,
            TodoItem.self,
            TodoCompletion.self,
            Vacation.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Die Datenbank konnte nicht geöffnet werden: \(error)")
        }
    }()
}
