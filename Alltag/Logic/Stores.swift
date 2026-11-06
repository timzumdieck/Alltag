import Foundation
import SwiftData

extension ModelContext {
    /// Speichert und plant anschließend die Mitteilungen neu.
    @MainActor
    func commit() {
        do {
            try save()
        } catch {
            print("Speichern fehlgeschlagen: \(error)")
        }
        NotificationScheduler.shared.scheduleSoon()
    }
}

// MARK: - To-Dos

struct TodoDraft {
    var kind: EntryKind
    var title: String
    var startDay: DayKey
    var timeMinutes: Int?
    var repeatKind: RepeatKind
    var weekdays: [Int]
    var dates: [DayKey]
    var reminderMinutes: Int?
    var carryOver: Bool
    var endMinutes: Int?
    var reminderOffset: Int?
    var location: String
}

enum EditScope {
    case all      // ganzes To-Do (bei einmaligen To-Dos)
    case single   // nur dieses Vorkommen
    case future   // dieses und alle zukünftigen
}

@MainActor
enum TodoStore {
    private static func completions(of todoID: UUID, in ctx: ModelContext) -> [TodoCompletion] {
        let all = (try? ctx.fetch(FetchDescriptor<TodoCompletion>())) ?? []
        return all.filter { $0.todoID == todoID }
    }

    static func toggle(_ todo: TodoItem, origin: DayKey, in ctx: ModelContext) {
        let existing = completions(of: todo.id, in: ctx).filter { $0.day == origin }
        if existing.isEmpty {
            let doneDay = todo.carries ? max(origin, Day.today) : origin
            ctx.insert(TodoCompletion(todoID: todo.id, day: origin, doneDay: doneDay))
        } else {
            for completion in existing { ctx.delete(completion) }
        }
        ctx.commit()
    }

    static func create(_ draft: TodoDraft, in ctx: ModelContext) {
        let todo = TodoItem()
        apply(draft, to: todo)
        ctx.insert(todo)
        ctx.commit()
    }

    private static func apply(_ draft: TodoDraft, to todo: TodoItem) {
        let isAppointment = draft.kind == .appointment
        todo.entryKind = draft.kind
        todo.title = draft.title
        todo.repeatKind = draft.repeatKind
        todo.timeMinutes = draft.timeMinutes
        todo.endMinutes = isAppointment && draft.timeMinutes != nil ? draft.endMinutes : nil
        todo.location = isAppointment ? draft.location.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        todo.reminderMinutes = isAppointment ? nil : draft.reminderMinutes
        todo.reminderOffset = isAppointment ? draft.reminderOffset : nil
        todo.carryOver = draft.kind == .todo && draft.carryOver
        todo.weekdays = draft.repeatKind == .weekdays ? draft.weekdays.sorted() : []
        todo.dates = draft.repeatKind == .dates ? Array(Set(draft.dates)).sorted() : []
        if draft.repeatKind == .dates, let first = todo.dates.first {
            todo.startDay = first
        } else {
            todo.startDay = draft.startDay
        }
    }

    static func update(_ todo: TodoItem, origin: DayKey, scope: EditScope, with draft: TodoDraft, in ctx: ModelContext) {
        let comps = completions(of: todo.id, in: ctx)

        switch scope {
        case .single where todo.isRecurring:
            // Ausnahme in der Serie + neues einmaliges To-Do
            todo.exceptions.append(origin)
            var single = draft
            single.repeatKind = .once
            let newTodo = TodoItem()
            apply(single, to: newTodo)
            ctx.insert(newTodo)
            for c in comps where c.day == origin {
                c.todoID = newTodo.id
                c.day = newTodo.startDay
                c.doneDay = max(c.doneDay, newTodo.startDay)
            }

        case .future where todo.isRecurring && origin > todo.startDay:
            // Serie bis gestern beenden, neue Serie ab diesem Tag
            todo.endDay = Day.adding(-1, to: origin)
            let newTodo = TodoItem()
            apply(draft, to: newTodo)
            newTodo.exceptions = todo.exceptions.filter { $0 >= origin }
            ctx.insert(newTodo)
            for c in comps where c.day >= origin {
                c.todoID = newTodo.id
            }

        default:
            // Ganzes To-Do bearbeiten
            let wasOnce = !todo.isRecurring
            let oldStart = todo.startDay
            apply(draft, to: todo)
            if wasOnce && !todo.isRecurring && oldStart != todo.startDay {
                for c in comps where c.day == oldStart {
                    c.day = todo.startDay
                    c.doneDay = max(c.doneDay, todo.startDay)
                }
            }
        }
        ctx.commit()
    }

    static func delete(_ todo: TodoItem, origin: DayKey, scope: EditScope, in ctx: ModelContext) {
        let comps = completions(of: todo.id, in: ctx)

        switch scope {
        case .single where todo.isRecurring:
            todo.exceptions.append(origin)
            for c in comps where c.day == origin { ctx.delete(c) }

        case .future where todo.isRecurring && origin > todo.startDay:
            todo.endDay = Day.adding(-1, to: origin)
            for c in comps where c.day >= origin { ctx.delete(c) }

        default:
            for c in comps { ctx.delete(c) }
            ctx.delete(todo)
        }
        ctx.commit()
    }
}

// MARK: - Training

@MainActor
enum TrainingStore {
    static func exerciseNames(in ctx: ModelContext) -> [UUID: String] {
        let all = (try? ctx.fetch(FetchDescriptor<Exercise>())) ?? []
        var map: [UUID: String] = [:]
        for exercise in all { map[exercise.id] = exercise.name }
        return map
    }

    /// Leere Struktur (Übungen mit leeren Sätzen) aus einer Einheit.
    static func structure(for plan: WorkoutPlan, names: [UUID: String]) -> [SessionExercise] {
        plan.entries.map { entry in
            SessionExercise(exerciseID: entry.exerciseID,
                            name: names[entry.exerciseID] ?? "Übung",
                            sets: Array(repeating: SetValue(), count: max(1, entry.sets)))
        }
    }

    /// Werte desselben Satzes vom letzten Mal, als die Übung gemacht wurde (egal in welcher Einheit).
    static func lastSets(exerciseID: UUID, upTo day: DayKey, excluding sessionID: UUID?, sessions: [WorkoutSession]) -> [SetValue] {
        let candidates = sessions
            .filter { $0.isCompleted && $0.id != sessionID && $0.day <= day }
            .sorted { lhs, rhs in
                if lhs.day != rhs.day { return lhs.day > rhs.day }
                return (lhs.completedAt ?? .distantPast) > (rhs.completedAt ?? .distantPast)
            }
        for session in candidates {
            let sets = session.exercises
                .filter { $0.exerciseID == exerciseID }
                .flatMap { $0.sets }
            if sets.contains(where: { !$0.isEmpty }) { return sets }
        }
        return []
    }

    /// Abhaken / wieder öffnen eines Trainings aus der To-Do-Liste.
    static func toggle(_ slot: TrainingSlot, in ctx: ModelContext) {
        if let session = slot.session {
            if session.isCompleted {
                if !session.hasData && slot.isPlanned {
                    ctx.delete(session)
                } else {
                    session.isCompleted = false
                    session.completedAt = nil
                    session.updatedAt = Date()
                }
            } else {
                if session.exercises.isEmpty, let plan = slot.plan {
                    session.exercises = structure(for: plan, names: exerciseNames(in: ctx))
                }
                session.isCompleted = true
                session.completedAt = Date()
                session.updatedAt = Date()
            }
        } else {
            let session = WorkoutSession(day: slot.day, planID: slot.plan?.id, planName: slot.name)
            if let plan = slot.plan {
                session.exercises = structure(for: plan, names: exerciseNames(in: ctx))
            }
            session.isCompleted = true
            session.completedAt = Date()
            ctx.insert(session)
        }
        ctx.commit()
    }

    /// Entfernt ein Training nur für diesen einen Tag. Die Einheit bleibt an allen anderen Tagen bestehen.
    static func skip(_ slot: TrainingSlot, in ctx: ModelContext) {
        if slot.isPlanned, let plan = slot.plan {
            if !plan.skippedDays.contains(slot.day) {
                plan.skippedDays.append(slot.day)
            }
            let sessions = (try? ctx.fetch(FetchDescriptor<WorkoutSession>())) ?? []
            for session in sessions where session.planID == plan.id && session.day == slot.day && !session.isCompleted {
                ctx.delete(session)
            }
        } else if let session = slot.session, !session.isCompleted {
            ctx.delete(session)
        }
        ctx.commit()
    }

    static func restoreSkipped(_ plan: WorkoutPlan, day: DayKey, in ctx: ModelContext) {
        plan.skippedDays.removeAll { $0 == day }
        ctx.commit()
    }

    static func startSpontaneous(_ plan: WorkoutPlan, day: DayKey, in ctx: ModelContext) {
        let session = WorkoutSession(day: day, planID: plan.id, planName: plan.name)
        session.exercises = structure(for: plan, names: exerciseNames(in: ctx))
        ctx.insert(session)
        ctx.commit()
    }

    static func removeSession(_ session: WorkoutSession, in ctx: ModelContext) {
        ctx.delete(session)
        ctx.commit()
    }

    static func savePlan(_ existing: WorkoutPlan?,
                         name: String,
                         entries: [PlanEntry],
                         weekdays: [Int],
                         specificDays: [DayKey],
                         in ctx: ModelContext) {
        let today = Day.today
        let newWeekdays = weekdays.sorted()

        if let plan = existing {
            plan.name = name
            plan.entries = entries
            plan.specificDays = Array(Set(specificDays)).sorted()
            var rules = plan.rules.sorted { $0.validFrom < $1.validFrom }
            let current = rules.last?.weekdays.sorted() ?? []
            if current != newWeekdays {
                if let last = rules.last, last.validFrom >= today {
                    rules[rules.count - 1] = ScheduleRule(validFrom: last.validFrom, weekdays: newWeekdays)
                } else {
                    rules.append(ScheduleRule(validFrom: today, weekdays: newWeekdays))
                }
                plan.rules = rules
            }
        } else {
            let plan = WorkoutPlan(name: name,
                                   entries: entries,
                                   rules: [ScheduleRule(validFrom: today, weekdays: newWeekdays)],
                                   specificDays: Array(Set(specificDays)).sorted())
            ctx.insert(plan)
        }
        ctx.commit()
    }

    static func deletePlan(_ plan: WorkoutPlan, in ctx: ModelContext) {
        // Abgeschlossene Trainings bleiben für die Statistik erhalten, offene Entwürfe werden entfernt.
        let sessions = (try? ctx.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        for session in sessions where session.planID == plan.id && !session.isCompleted {
            ctx.delete(session)
        }
        ctx.delete(plan)
        ctx.commit()
    }

    static func findOrCreateExercise(named rawName: String, in ctx: ModelContext) -> Exercise {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = (try? ctx.fetch(FetchDescriptor<Exercise>())) ?? []
        if let existing = all.first(where: { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            return existing
        }
        let exercise = Exercise(name: name)
        ctx.insert(exercise)
        try? ctx.save()
        return exercise
    }

    static func renameExercise(_ exercise: Exercise, to rawName: String, in ctx: ModelContext) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        exercise.name = name
        let sessions = (try? ctx.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        for session in sessions {
            var list = session.exercises
            var changed = false
            for i in list.indices where list[i].exerciseID == exercise.id {
                list[i].name = name
                changed = true
            }
            if changed { session.exercises = list }
        }
        ctx.commit()
    }
}
