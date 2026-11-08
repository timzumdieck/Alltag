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
    case once, daily, weekdays, dates

    var id: String { rawValue }

    var label: String {
        switch self {
        case .once: return "Einmalig"
        case .daily: return "Täglich"
        case .weekdays: return "Bestimmte Wochentage"
        case .dates: return "Genaue Daten"
        }
    }
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
    var createdAt: Date = Date()

    init(id: UUID = UUID(),
         name: String,
         entries: [PlanEntry] = [],
         rules: [ScheduleRule] = [],
         specificDays: [String] = [],
         skippedDays: [String] = [],
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.entriesData = JSONBlob.encode(entries)
        self.rulesData = JSONBlob.encode(rules)
        self.specificDays = specificDays
        self.skippedDays = skippedDays
        self.createdAt = createdAt
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

    var isRecurring: Bool { repeatKind != .once }

    var entryKind: EntryKind {
        get { EntryKind(rawValue: kindRaw) ?? .todo }
        set { kindRaw = newValue.rawValue }
    }

    /// „Auf den nächsten Tag verschieben“ gilt nur für normale To-Dos.
    var carries: Bool { carryOver && entryKind == .todo }

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
