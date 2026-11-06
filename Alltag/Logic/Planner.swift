import Foundation

/// Ein Training an einem bestimmten Tag – geplant (aus einer Einheit) und/oder bereits begonnen (Session).
struct TrainingSlot: Identifiable {
    let id: String
    let day: DayKey
    let plan: WorkoutPlan?
    let session: WorkoutSession?
    /// true = kommt aus dem Trainingsplan, false = spontan gestartet
    let isPlanned: Bool

    var name: String { plan?.name ?? session?.planName ?? "Training" }
    var isDone: Bool { session?.isCompleted ?? false }
}

struct TodoRef {
    let todo: TodoItem
    let origin: DayKey
}

/// Eine Zeile im To-Do-Tab (normales To-Do oder Training).
struct TodoRow: Identifiable {
    enum Kind {
        case todo(TodoItem, DayKey)   // To-Do + ursprünglicher Tag des Vorkommens
        case training(TrainingSlot)
    }

    let id: String
    let kind: Kind
    let title: String
    let timeMinutes: Int?
    let isDone: Bool
    let doneAt: Date?
    /// Gesetzt, wenn das To-Do von einem früheren Tag verschoben wurde.
    let carriedFrom: DayKey?
    let isRecurring: Bool
    let entryKind: EntryKind
    let endMinutes: Int?
    let location: String
    /// Gewohnheiten: wie oft in Folge erledigt
    let streak: Int

    /// Termine werden nicht abgehakt.
    var isCheckable: Bool { entryKind != .appointment }

    var trainingSlot: TrainingSlot? {
        if case let .training(slot) = kind { return slot }
        return nil
    }

    /// Für normale To-Dos: das To-Do und der ursprüngliche Tag.
    var todoRef: TodoRef? {
        if case let .todo(todo, origin) = kind { return TodoRef(todo: todo, origin: origin) }
        return nil
    }

    var isTraining: Bool {
        if case .training = kind { return true }
        return false
    }

    var signature: String { "\(id)|\(isDone)" }
}

/// Berechnet aus den gespeicherten Daten, was an welchem Tag ansteht.
struct Planner {
    let today: DayKey

    private struct PlanInfo {
        let plan: WorkoutPlan
        let rules: [ScheduleRule]
        let specific: Set<DayKey>
        let skipped: Set<DayKey>
    }

    private let todos: [TodoItem]
    private let todoByID: [UUID: TodoItem]
    private let completionByKey: [String: TodoCompletion]
    private let lateDoneByDay: [DayKey: [TodoCompletion]]
    private let planInfos: [PlanInfo]
    private let sessionsByDay: [DayKey: [WorkoutSession]]

    init(todos: [TodoItem],
         completions: [TodoCompletion],
         plans: [WorkoutPlan],
         sessions: [WorkoutSession],
         today: DayKey = Day.today) {
        self.today = today
        self.todos = todos

        var byID: [UUID: TodoItem] = [:]
        for todo in todos { byID[todo.id] = todo }
        self.todoByID = byID

        var byKey: [String: TodoCompletion] = [:]
        var late: [DayKey: [TodoCompletion]] = [:]
        for completion in completions {
            byKey[Planner.key(completion.todoID, completion.day)] = completion
            if completion.doneDay > completion.day {
                late[completion.doneDay, default: []].append(completion)
            }
        }
        self.completionByKey = byKey
        self.lateDoneByDay = late

        self.planInfos = plans.map { plan in
            PlanInfo(plan: plan,
                     rules: plan.rules.sorted { $0.validFrom < $1.validFrom },
                     specific: Set(plan.specificDays),
                     skipped: Set(plan.skippedDays))
        }

        var sessionMap: [DayKey: [WorkoutSession]] = [:]
        for session in sessions { sessionMap[session.day, default: []].append(session) }
        for (day, list) in sessionMap {
            sessionMap[day] = list.sorted { $0.updatedAt < $1.updatedAt }
        }
        self.sessionsByDay = sessionMap
    }

    static func key(_ id: UUID, _ day: DayKey) -> String { "\(id.uuidString)|\(day)" }

    // MARK: - Regeln

    /// Findet das To-Do (laut Wiederholungsregel) an diesem Tag statt?
    static func occurs(_ todo: TodoItem, on day: DayKey) -> Bool {
        guard !todo.startDay.isEmpty, day >= todo.startDay else { return false }
        if let end = todo.endDay, day > end { return false }
        if todo.exceptions.contains(day) { return false }
        switch todo.repeatKind {
        case .once: return day == todo.startDay
        case .daily: return true
        case .weekdays: return todo.weekdays.contains(Day.weekday(day))
        case .dates: return todo.dates.contains(day)
        }
    }

    private func planOccurs(_ info: PlanInfo, on day: DayKey) -> Bool {
        !info.skipped.contains(day) && planScheduled(info, on: day)
    }

    /// Laut Plan vorgesehen (ohne Berücksichtigung entfernter Tage).
    private func planScheduled(_ info: PlanInfo, on day: DayKey) -> Bool {
        if info.specific.contains(day) { return true }
        guard let rule = info.rules.last(where: { $0.validFrom <= day }) else { return false }
        return rule.weekdays.contains(Day.weekday(day))
    }

    // MARK: - Trainings

    func trainings(on day: DayKey) -> [TrainingSlot] {
        let sessions = sessionsByDay[day] ?? []
        var used = Set<UUID>()
        var slots: [TrainingSlot] = []

        for info in planInfos where planOccurs(info, on: day) {
            let session = sessions.first { $0.planID == info.plan.id && !used.contains($0.id) }
            if let session { used.insert(session.id) }
            slots.append(TrainingSlot(id: "plan-\(info.plan.id.uuidString)",
                                      day: day,
                                      plan: info.plan,
                                      session: session,
                                      isPlanned: true))
        }

        for session in sessions where !used.contains(session.id) {
            let plan = planInfos.first { $0.plan.id == session.planID }?.plan
            slots.append(TrainingSlot(id: "session-\(session.id.uuidString)",
                                      day: day,
                                      plan: plan,
                                      session: session,
                                      isPlanned: false))
        }
        return slots
    }

    /// Einheiten, die an diesem Tag geplant wären, aber entfernt wurden.
    func skippedPlans(on day: DayKey) -> [WorkoutPlan] {
        planInfos
            .filter { $0.skipped.contains(day) && planScheduled($0, on: day) }
            .map { $0.plan }
    }

    func hasTraining(on day: DayKey) -> Bool {
        if !(sessionsByDay[day] ?? []).isEmpty { return true }
        return planInfos.contains { planOccurs($0, on: day) }
    }

    // MARK: - To-Dos

    /// Alle Zeilen eines Tages (optional inklusive Trainings), sortiert:
    /// offene zuerst (nach Uhrzeit), erledigte unten (in der Reihenfolge des Abhakens).
    func todoRows(on day: DayKey, includeTrainings: Bool = true, includeStreaks: Bool = false) -> [TodoRow] {
        var rows: [TodoRow] = []

        for todo in todos where Planner.occurs(todo, on: day) {
            let completion = todo.entryKind == .appointment ? nil : completionByKey[Planner.key(todo.id, day)]
            if todo.carries {
                // Ein verschiebbares To-Do steht an genau einem Tag:
                // erledigt → am Erledigungstag, offen → am ursprünglichen Tag bzw. heute.
                let displayDay: DayKey
                if let completion {
                    displayDay = max(day, completion.doneDay)
                } else {
                    displayDay = max(day, today)
                }
                if displayDay != day { continue }
            }
            rows.append(makeRow(todo, origin: day, completion: completion, displayDay: day, includeStreak: includeStreaks))
        }

        // Verschobene To-Dos, die an diesem Tag erledigt wurden
        for completion in lateDoneByDay[day] ?? [] {
            guard let todo = todoByID[completion.todoID],
                  todo.carries,
                  Planner.occurs(todo, on: completion.day) else { continue }
            rows.append(makeRow(todo, origin: completion.day, completion: completion, displayDay: day))
        }

        // Noch offene, verschobene To-Dos erscheinen heute
        if day == today {
            for todo in todos where todo.carries {
                for origin in openPastOccurrences(of: todo) {
                    rows.append(makeRow(todo, origin: origin, completion: nil, displayDay: day))
                }
            }
        }

        if includeTrainings {
            for slot in trainings(on: day) {
                rows.append(TodoRow(id: "training-\(slot.id)",
                                    kind: .training(slot),
                                    title: slot.name,
                                    timeMinutes: nil,
                                    isDone: slot.isDone,
                                    doneAt: slot.session?.completedAt,
                                    carriedFrom: nil,
                                    isRecurring: slot.isPlanned,
                                    entryKind: .todo,
                                    endMinutes: nil,
                                    location: "",
                                    streak: 0))
            }
        }

        return rows.sorted(by: Planner.rowOrder)
    }

    func hasTodos(on day: DayKey) -> Bool {
        !todoRows(on: day, includeTrainings: false).isEmpty
    }

    struct DayMarkers {
        var training = false
        var appointment = false
        var task = false
    }

    /// Für die Punkte im Kalender.
    func markers(on day: DayKey) -> DayMarkers {
        var markers = DayMarkers()
        markers.training = hasTraining(on: day)
        for row in todoRows(on: day, includeTrainings: false) {
            // Gewohnheiten bekommen keinen Punkt – sonst hätte bei täglichen Gewohnheiten jeder Tag einen.
            switch row.entryKind {
            case .appointment: markers.appointment = true
            case .todo: markers.task = true
            case .habit: break
            }
        }
        return markers
    }

    /// Wie oft wurde die Gewohnheit zuletzt ohne Unterbrechung erledigt?
    private func habitStreak(_ todo: TodoItem, upTo day: DayKey) -> Int {
        var current = day
        if completionByKey[Planner.key(todo.id, current)] == nil {
            current = Day.adding(-1, to: current)   // heute zählt erst, wenn erledigt
        }
        var count = 0
        var steps = 0
        while current >= todo.startDay && steps < 400 {
            steps += 1
            if Planner.occurs(todo, on: current) {
                if completionByKey[Planner.key(todo.id, current)] != nil {
                    count += 1
                } else {
                    break
                }
            }
            current = Day.adding(-1, to: current)
        }
        return count
    }

    private func openPastOccurrences(of todo: TodoItem) -> [DayKey] {
        let yesterday = Day.adding(-1, to: today)
        guard !todo.startDay.isEmpty, todo.startDay <= yesterday else { return [] }

        var result: [DayKey] = []
        let isOpen: (DayKey) -> Bool = { day in
            Planner.occurs(todo, on: day) && completionByKey[Planner.key(todo.id, day)] == nil
        }

        switch todo.repeatKind {
        case .once:
            if isOpen(todo.startDay) { result.append(todo.startDay) }
        case .dates:
            for day in todo.dates.sorted() where day <= yesterday && isOpen(day) {
                result.append(day)
            }
        case .daily, .weekdays:
            // Höchstens 120 Tage zurückblicken
            var day = max(todo.startDay, Day.adding(-120, to: today))
            let end = min(yesterday, todo.endDay ?? yesterday)
            while day <= end {
                if isOpen(day) { result.append(day) }
                day = Day.adding(1, to: day)
            }
        }
        return result
    }

    private func makeRow(_ todo: TodoItem, origin: DayKey, completion: TodoCompletion?, displayDay: DayKey, includeStreak: Bool = false) -> TodoRow {
        let streak = (includeStreak && todo.entryKind == .habit) ? habitStreak(todo, upTo: displayDay) : 0
        return TodoRow(id: "todo-\(todo.id.uuidString)-\(origin)",
                kind: .todo(todo, origin),
                title: todo.title,
                timeMinutes: todo.timeMinutes,
                isDone: completion != nil,
                doneAt: completion?.completedAt,
                carriedFrom: origin != displayDay ? origin : nil,
                isRecurring: todo.isRecurring,
                entryKind: todo.entryKind,
                endMinutes: todo.endMinutes,
                location: todo.location,
                streak: streak)
    }

    static func rowOrder(_ a: TodoRow, _ b: TodoRow) -> Bool {
        if a.isDone != b.isDone { return !a.isDone }
        if a.isDone {
            let da = a.doneAt ?? .distantPast
            let db = b.doneAt ?? .distantPast
            if da != db { return da < db }
        } else {
            let ta = a.timeMinutes ?? Int.max
            let tb = b.timeMinutes ?? Int.max
            if ta != tb { return ta < tb }
            if a.isTraining != b.isTraining { return a.isTraining }
            let ca = a.carriedFrom != nil
            let cb = b.carriedFrom != nil
            if ca != cb { return ca }
        }
        let c = a.title.localizedCaseInsensitiveCompare(b.title)
        if c != .orderedSame { return c == .orderedAscending }
        return a.id < b.id
    }
}
