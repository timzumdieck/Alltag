import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupData: Codable {
    struct ExerciseDTO: Codable {
        var id: UUID
        var name: String
        var createdAt: Date
    }

    struct PlanDTO: Codable {
        var id: UUID
        var name: String
        var entries: [PlanEntry]
        var rules: [ScheduleRule]
        var specificDays: [String]
        var createdAt: Date
        var skippedDays: [String]?
    }

    struct SessionDTO: Codable {
        var id: UUID
        var day: String
        var planID: UUID?
        var planName: String
        var exercises: [SessionExercise]
        var isCompleted: Bool
        var completedAt: Date?
        var updatedAt: Date
    }

    struct TodoDTO: Codable {
        var id: UUID
        var title: String
        var startDay: String
        var endDay: String?
        var timeMinutes: Int?
        var repeatKind: String
        var weekdays: [Int]
        var dates: [String]
        var exceptions: [String]
        var reminderMinutes: Int?
        var carryOver: Bool
        var createdAt: Date
        var kind: String?
        var endMinutes: Int?
        var reminderOffset: Int?
        var location: String?
    }

    struct CompletionDTO: Codable {
        var id: UUID
        var todoID: UUID
        var day: String
        var doneDay: String
        var completedAt: Date
    }

    var format: Int
    var exportedAt: Date
    var exercises: [ExerciseDTO]
    var plans: [PlanDTO]
    var sessions: [SessionDTO]
    var todos: [TodoDTO]
    var completions: [CompletionDTO]
    var settings: [String: Int]
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@MainActor
enum BackupService {
    static func export(_ ctx: ModelContext) throws -> Data {
        let exercises = (try? ctx.fetch(FetchDescriptor<Exercise>())) ?? []
        let plans = (try? ctx.fetch(FetchDescriptor<WorkoutPlan>())) ?? []
        let sessions = (try? ctx.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let todos = (try? ctx.fetch(FetchDescriptor<TodoItem>())) ?? []
        let completions = (try? ctx.fetch(FetchDescriptor<TodoCompletion>())) ?? []

        var settings: [String: Int] = [:]
        let defaults = UserDefaults.standard
        for key in PrefKey.boolDefaults.keys { settings[key] = defaults.bool(forKey: key) ? 1 : 0 }
        for key in PrefKey.intDefaults.keys { settings[key] = defaults.integer(forKey: key) }

        var exerciseDTOs: [BackupData.ExerciseDTO] = []
        for e in exercises {
            exerciseDTOs.append(BackupData.ExerciseDTO(id: e.id, name: e.name, createdAt: e.createdAt))
        }

        var planDTOs: [BackupData.PlanDTO] = []
        for p in plans {
            planDTOs.append(BackupData.PlanDTO(id: p.id, name: p.name, entries: p.entries, rules: p.rules,
                                               specificDays: p.specificDays, createdAt: p.createdAt,
                                               skippedDays: p.skippedDays))
        }

        var sessionDTOs: [BackupData.SessionDTO] = []
        for s in sessions {
            sessionDTOs.append(BackupData.SessionDTO(id: s.id, day: s.day, planID: s.planID, planName: s.planName,
                                                     exercises: s.exercises, isCompleted: s.isCompleted,
                                                     completedAt: s.completedAt, updatedAt: s.updatedAt))
        }

        var todoDTOs: [BackupData.TodoDTO] = []
        for t in todos {
            todoDTOs.append(BackupData.TodoDTO(id: t.id, title: t.title, startDay: t.startDay, endDay: t.endDay,
                                               timeMinutes: t.timeMinutes, repeatKind: t.repeatRaw,
                                               weekdays: t.weekdays, dates: t.dates, exceptions: t.exceptions,
                                               reminderMinutes: t.reminderMinutes, carryOver: t.carryOver,
                                               createdAt: t.createdAt, kind: t.kindRaw, endMinutes: t.endMinutes,
                                               reminderOffset: t.reminderOffset, location: t.location))
        }

        var completionDTOs: [BackupData.CompletionDTO] = []
        for c in completions {
            completionDTOs.append(BackupData.CompletionDTO(id: c.id, todoID: c.todoID, day: c.day,
                                                           doneDay: c.doneDay, completedAt: c.completedAt))
        }

        let backup = BackupData(format: 2,
                                exportedAt: Date(),
                                exercises: exerciseDTOs,
                                plans: planDTOs,
                                sessions: sessionDTOs,
                                todos: todoDTOs,
                                completions: completionDTOs,
                                settings: settings)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    static func decode(_ data: Data) throws -> BackupData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupData.self, from: data)
    }

    /// Ersetzt alle vorhandenen Daten durch das Backup.
    static func restore(_ backup: BackupData, into ctx: ModelContext) {
        for item in (try? ctx.fetch(FetchDescriptor<TodoCompletion>())) ?? [] { ctx.delete(item) }
        for item in (try? ctx.fetch(FetchDescriptor<TodoItem>())) ?? [] { ctx.delete(item) }
        for item in (try? ctx.fetch(FetchDescriptor<WorkoutSession>())) ?? [] { ctx.delete(item) }
        for item in (try? ctx.fetch(FetchDescriptor<WorkoutPlan>())) ?? [] { ctx.delete(item) }
        for item in (try? ctx.fetch(FetchDescriptor<Exercise>())) ?? [] { ctx.delete(item) }
        try? ctx.save()

        for e in backup.exercises {
            ctx.insert(Exercise(id: e.id, name: e.name, createdAt: e.createdAt))
        }
        for p in backup.plans {
            ctx.insert(WorkoutPlan(id: p.id, name: p.name, entries: p.entries, rules: p.rules,
                                   specificDays: p.specificDays, skippedDays: p.skippedDays ?? [], createdAt: p.createdAt))
        }
        for s in backup.sessions {
            ctx.insert(WorkoutSession(id: s.id, day: s.day, planID: s.planID, planName: s.planName, exercises: s.exercises, isCompleted: s.isCompleted, completedAt: s.completedAt, updatedAt: s.updatedAt))
        }
        for t in backup.todos {
            let todo = TodoItem(id: t.id, title: t.title, startDay: t.startDay, createdAt: t.createdAt)
            todo.endDay = t.endDay
            todo.timeMinutes = t.timeMinutes
            todo.repeatRaw = t.repeatKind
            todo.weekdays = t.weekdays
            todo.dates = t.dates
            todo.exceptions = t.exceptions
            todo.reminderMinutes = t.reminderMinutes
            todo.carryOver = t.carryOver
            todo.kindRaw = t.kind ?? EntryKind.todo.rawValue
            todo.endMinutes = t.endMinutes
            todo.reminderOffset = t.reminderOffset
            todo.location = t.location ?? ""
            ctx.insert(todo)
        }
        for c in backup.completions {
            ctx.insert(TodoCompletion(id: c.id, todoID: c.todoID, day: c.day, doneDay: c.doneDay, completedAt: c.completedAt))
        }

        let defaults = UserDefaults.standard
        for (key, value) in backup.settings {
            if PrefKey.boolDefaults[key] != nil {
                defaults.set(value != 0, forKey: key)
            } else if PrefKey.intDefaults[key] != nil {
                defaults.set(value, forKey: key)
            }
        }

        ctx.commit()
    }
}
