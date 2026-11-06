import Foundation
import SwiftData
import UserNotifications
import BackgroundTasks

enum AppConstants {
    static let refreshTaskID = "alltag.refresh"
}

// MARK: - Einstellungen

enum PrefKey {
    static let morningOn = "notif.morning.on"
    static let morningTime = "notif.morning.time"
    static let trainingOn = "notif.training.on"
    static let trainingTime = "notif.training.time"
    static let eveningOn = "notif.evening.on"
    static let eveningTime = "notif.evening.time"
    static let todoOn = "notif.todo.on"
    static let quietOn = "notif.quiet.on"
    static let quietStart = "notif.quiet.start"
    static let quietEnd = "notif.quiet.end"

    static let boolDefaults: [String: Bool] = [
        morningOn: true, trainingOn: true, eveningOn: true, todoOn: true, quietOn: false
    ]
    static let intDefaults: [String: Int] = [
        morningTime: 7 * 60, trainingTime: 17 * 60, eveningTime: 20 * 60,
        quietStart: 22 * 60, quietEnd: 7 * 60
    ]

    static func registerDefaults() {
        var defaults: [String: Any] = [:]
        for (key, value) in boolDefaults { defaults[key] = value }
        for (key, value) in intDefaults { defaults[key] = value }
        UserDefaults.standard.register(defaults: defaults)
    }
}

struct NotificationPrefs {
    var morningOn: Bool
    var morningTime: Int
    var trainingOn: Bool
    var trainingTime: Int
    var eveningOn: Bool
    var eveningTime: Int
    var todoOn: Bool
    var quietOn: Bool
    var quietStart: Int
    var quietEnd: Int

    static func load() -> NotificationPrefs {
        let d = UserDefaults.standard
        return NotificationPrefs(
            morningOn: d.bool(forKey: PrefKey.morningOn),
            morningTime: d.integer(forKey: PrefKey.morningTime),
            trainingOn: d.bool(forKey: PrefKey.trainingOn),
            trainingTime: d.integer(forKey: PrefKey.trainingTime),
            eveningOn: d.bool(forKey: PrefKey.eveningOn),
            eveningTime: d.integer(forKey: PrefKey.eveningTime),
            todoOn: d.bool(forKey: PrefKey.todoOn),
            quietOn: d.bool(forKey: PrefKey.quietOn),
            quietStart: d.integer(forKey: PrefKey.quietStart),
            quietEnd: d.integer(forKey: PrefKey.quietEnd)
        )
    }

    /// Liegt die Uhrzeit (Minuten seit Mitternacht) in der Ruhezeit?
    func isQuiet(_ minutes: Int) -> Bool {
        guard quietOn, quietStart != quietEnd else { return false }
        if quietStart < quietEnd {
            return minutes >= quietStart && minutes < quietEnd
        }
        return minutes >= quietStart || minutes < quietEnd   // über Mitternacht
    }
}

// MARK: - Planung

/// iOS erlaubt höchstens 64 geplante Mitteilungen. Deshalb werden immer nur die nächsten
/// Tage geplant – bei jedem App-Start, nach jeder Änderung und per Hintergrundaktualisierung.
@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    private let daysAhead = 7
    private let maxRequests = 60
    private var pendingTask: Task<Void, Never>?

    private struct Planned {
        let id: String
        let date: Date
        let title: String
        let body: String
    }

    /// Bündelt mehrere schnelle Änderungen zu einer Neuplanung.
    func scheduleSoon() {
        pendingTask?.cancel()
        pendingTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            if Task.isCancelled { return }
            await self.rescheduleNow()
        }
    }

    func rescheduleNow() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let status = settings.authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            center.removeAllPendingNotificationRequests()
            return
        }

        let ctx = Persistence.container.mainContext
        let todos = (try? ctx.fetch(FetchDescriptor<TodoItem>())) ?? []
        let completions = (try? ctx.fetch(FetchDescriptor<TodoCompletion>())) ?? []
        let plans = (try? ctx.fetch(FetchDescriptor<WorkoutPlan>())) ?? []
        let sessions = (try? ctx.fetch(FetchDescriptor<WorkoutSession>())) ?? []

        let prefs = NotificationPrefs.load()
        let now = Date()
        let today = Day.today
        var items: [Planned] = []

        // Ein Tag mehr, damit auch „1 Tag vorher“-Erinnerungen für Termine erfasst werden.
        for offset in 0...daysAhead {
            let day = Day.adding(offset, to: today)
            let isSummaryDay = offset < daysAhead
            // Planner aus Sicht dieses Tages: offene, verschiebbare To-Dos wandern mit.
            let planner = Planner(todos: todos, completions: completions, plans: plans, sessions: sessions, today: day)
            let rows = planner.todoRows(on: day)
            let trainings = planner.trainings(on: day)
            let openTasks = rows.filter { $0.entryKind == .todo && !$0.isTraining && !$0.isDone }
            let openHabits = rows.filter { $0.entryKind == .habit && !$0.isDone }
            let appointments = rows
                .filter { $0.entryKind == .appointment }
                .sorted { ($0.timeMinutes ?? -1) < ($1.timeMinutes ?? -1) }

            if prefs.morningOn && isSummaryDay {
                var parts: [String] = []
                let names = trainings.map { $0.name }
                if !names.isEmpty {
                    parts.append("Training: " + names.joined(separator: ", "))
                }
                if !appointments.isEmpty {
                    var text = Fmt.appointmentCount(appointments.count)
                    if let first = appointments.first(where: { $0.timeMinutes != nil })?.timeMinutes {
                        text += " ab \(Day.timeString(first))"
                    }
                    parts.append(text)
                }
                if !openTasks.isEmpty { parts.append(Fmt.todoCount(openTasks.count)) }
                if !openHabits.isEmpty { parts.append(Fmt.habitCount(openHabits.count)) }
                items.append(Planned(id: "morning-\(day)",
                                     date: Day.date(day, minutes: prefs.morningTime),
                                     title: "Guten Morgen",
                                     body: parts.isEmpty ? "Heute steht nichts an." : parts.joined(separator: " · ")))
            }

            if prefs.trainingOn && isSummaryDay {
                let open = trainings.filter { !$0.isDone }
                if !open.isEmpty {
                    items.append(Planned(id: "training-\(day)",
                                         date: Day.date(day, minutes: prefs.trainingTime),
                                         title: "Training",
                                         body: "Heute steht an: " + open.map { $0.name }.joined(separator: ", ")))
                }
            }

            if prefs.eveningOn && isSummaryDay {
                let openTodoCount = rows.filter { $0.entryKind == .todo && !$0.isDone }.count   // inkl. Training
                let openHabitCount = openHabits.count
                var parts: [String] = []
                if openTodoCount > 0 { parts.append(Fmt.todoCount(openTodoCount)) }
                if openHabitCount > 0 { parts.append(Fmt.habitCount(openHabitCount)) }
                if !parts.isEmpty {
                    items.append(Planned(id: "evening-\(day)",
                                         date: Day.date(day, minutes: prefs.eveningTime),
                                         title: "Abend-Check",
                                         body: "Noch \(parts.joined(separator: " und ")) offen"))
                }
            }

            if prefs.todoOn {
                for row in rows where !row.isDone {
                    guard let ref = row.todoRef, ref.origin == day else { continue }
                    let todo = ref.todo
                    if todo.entryKind == .appointment {
                        guard let offset = todo.reminderOffset else { continue }
                        let start = Day.date(day, minutes: todo.timeMinutes ?? 9 * 60)
                        var body = todo.timeMinutes.map { "Beginnt um \(Day.timeString($0)) Uhr" } ?? "Ganztägiger Termin"
                        if offset >= 1440 { body = "Morgen: " + body }
                        if !todo.location.isEmpty { body += " · \(todo.location)" }
                        items.append(Planned(id: "todo-\(todo.id.uuidString)-\(day)",
                                             date: start.addingTimeInterval(TimeInterval(-offset * 60)),
                                             title: todo.title,
                                             body: body))
                    } else {
                        guard let minutes = todo.reminderMinutes else { continue }
                        let body = todo.timeMinutes.map { "Fällig um \(Day.timeString($0)) Uhr" }
                            ?? (todo.entryKind == .habit ? "Gewohnheit" : "Erinnerung")
                        items.append(Planned(id: "todo-\(todo.id.uuidString)-\(day)",
                                             date: Day.date(day, minutes: minutes),
                                             title: todo.title,
                                             body: body))
                    }
                }
            }
        }

        let upcoming = items
            .filter { $0.date > now.addingTimeInterval(5) }
            .filter { !prefs.isQuiet(Day.minutes(of: $0.date)) }
            .sorted { $0.date < $1.date }
            .prefix(maxRequests)

        center.removeAllPendingNotificationRequests()

        for item in upcoming {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            // Absoluter Zeitpunkt (in Berlin berechnet) → Komponenten im Gerätekalender
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    // MARK: - Hintergrundaktualisierung

    func submitBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: AppConstants.refreshTaskID)
        request.earliestBeginDate = Date().addingTimeInterval(4 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Hintergrundaktualisierung konnte nicht angemeldet werden: \(error)")
        }
    }

    func handleBackgroundRefresh() async {
        submitBackgroundRefresh()
        await rescheduleNow()
    }

    // MARK: - Berechtigung & Test

    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    func sendTestNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "Test-Mitteilung"
        content.body = "So sehen deine Mitteilungen aus."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
