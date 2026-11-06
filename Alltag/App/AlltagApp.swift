import SwiftUI
import SwiftData
import UserNotifications
import Observation

@main
struct AlltagApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState.shared

    init() {
        PrefKey.registerDefaults()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(\.locale, Day.locale)
                .environment(\.timeZone, Day.timeZone)
                .environment(\.calendar, Day.calendar)
                .tint(Theme.accent)
        }
        .modelContainer(Persistence.container)
        .backgroundTask(.appRefresh(AppConstants.refreshTaskID)) {
            await NotificationScheduler.shared.handleBackgroundRefresh()
        }
    }
}

// MARK: - App-Zustand (Tabs, gewählte Tage)

@Observable
final class AppState {
    static let shared = AppState()

    enum Tab: Hashable {
        case training, calendar, todos
    }

    var tab: Tab = .calendar
    var trainingDay: DayKey = Day.today
    var todoDay: DayKey = Day.today
    var calendarSelected: DayKey = Day.today
    var calendarMonth: DayKey = Day.firstOfMonth(Day.today)
    var showSettings = false

    @ObservationIgnored private var lastActiveDay: DayKey = Day.today

    /// Springt nach Mitternacht automatisch auf den neuen Tag.
    func refreshDayIfNeeded() {
        let today = Day.today
        guard today != lastActiveDay else { return }
        lastActiveDay = today
        trainingDay = today
        todoDay = today
        calendarSelected = today
        calendarMonth = Day.firstOfMonth(today)
    }

    func open(_ tab: Tab, day: DayKey) {
        switch tab {
        case .training: trainingDay = day
        case .todos: todoDay = day
        case .calendar:
            calendarSelected = day
            calendarMonth = Day.firstOfMonth(day)
        }
        self.tab = tab
    }
}

// MARK: - AppDelegate (Mitteilungen im Vordergrund + Tippen auf Mitteilung)

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        DispatchQueue.main.async {
            let state = AppState.shared
            state.refreshDayIfNeeded()
            if identifier.hasPrefix("training-") {
                state.open(.training, day: Day.today)
            } else if identifier.hasPrefix("morning-") {
                state.open(.calendar, day: Day.today)
            } else if identifier.hasPrefix("evening-") || identifier.hasPrefix("todo-") {
                state.open(.todos, day: Day.today)
            }
            completionHandler()
        }
    }
}

// MARK: - Hauptansicht mit Tab-Leiste

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app

        TabView(selection: $app.tab) {
            TrainingTab()
                .tabItem { Label("Training", systemImage: "dumbbell") }
                .tag(AppState.Tab.training)

            CalendarTab()
                .tabItem { Label("Kalender", systemImage: "calendar") }
                .tag(AppState.Tab.calendar)

            TodoTab()
                .tabItem { Label("To-Dos", systemImage: "checklist") }
                .tag(AppState.Tab.todos)
        }
        .sheet(isPresented: $app.showSettings) {
            SettingsView()
        }
        .task {
            await NotificationScheduler.shared.requestAuthorizationIfNeeded()
            await NotificationScheduler.shared.rescheduleNow()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                app.refreshDayIfNeeded()
                NotificationScheduler.shared.scheduleSoon()
            case .background:
                NotificationScheduler.shared.submitBackgroundRefresh()
            default:
                break
            }
        }
    }
}

/// Zahnrad oben links in jedem Tab.
struct SettingsButton: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Button {
            app.showSettings = true
        } label: {
            Image(systemName: "gearshape")
                .fontWeight(.light)
        }
        .accessibilityLabel("Einstellungen")
    }
}
