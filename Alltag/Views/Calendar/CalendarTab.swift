import SwiftUI
import UIKit
import SwiftData

struct CalendarTab: View {
    @Environment(AppState.self) private var app

    @Query private var todos: [TodoItem]
    @Query private var completions: [TodoCompletion]
    @Query private var plans: [WorkoutPlan]
    @Query private var sessions: [WorkoutSession]

    @State private var forward = true
    @State private var popupDay: DayKey?

    var body: some View {
        let planner = Planner(todos: todos, completions: completions, plans: plans, sessions: sessions)

        NavigationStack {
            VStack(spacing: 0) {
                header
                weekdayHeader

                ZStack {
                    MonthGridView(month: app.calendarMonth,
                                  selected: app.calendarSelected,
                                  planner: planner,
                                  onTap: { day in select(day) },
                                  onDoubleTap: { day in
                                      select(day)
                                      popupDay = day
                                  })
                        .id(app.calendarMonth)
                        .transition(.asymmetric(
                            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                }
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onEnded { value in
                            let dx = value.translation.width
                            guard abs(dx) > abs(value.translation.height), abs(dx) > 40 else { return }
                            changeMonth(dx < 0 ? 1 : -1)
                        }
                )

                Divider()
                    .padding(.top, 6)

                DayAgendaView(day: app.calendarSelected, planner: planner)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SettingsButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Heute") { goToToday() }
                }
            }
            .alert(popupDay.map { Day.fullDate($0) } ?? "",
                   isPresented: Binding(get: { popupDay != nil }, set: { if !$0 { popupDay = nil } }),
                   presenting: popupDay) { day in
                Button("To-Dos") { app.open(.todos, day: day) }
                Button("Training") { app.open(.training, day: day) }
                Button("Abbrechen", role: .cancel) {}
            } message: { _ in
                Text("Was möchtest du öffnen?")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Day.yearString(app.calendarMonth))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.accent)
                Text(Day.monthName(app.calendarMonth))
                    .font(.largeTitle.weight(.bold))
                    .contentTransition(.opacity)
            }
            Spacer()
            HStack(spacing: 4) {
                Button { changeMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .light))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Vorheriger Monat")
                Button { changeMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 20, weight: .light))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Nächster Monat")
            }
            .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Day.weekdayOrder, id: \.self) { weekday in
                Text(Day.shortWeekdayName(weekday))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(weekday == 1 || weekday == 7 ? Color.secondary.opacity(0.7) : Color.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private func select(_ day: DayKey) {
        haptic(.soft)
        app.calendarSelected = day
    }

    private func changeMonth(_ delta: Int) {
        forward = delta > 0
        Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.28)) {
                app.calendarMonth = Day.addingMonths(delta, to: app.calendarMonth)
            }
        }
    }

    private func goToToday() {
        let today = Day.today
        let month = Day.firstOfMonth(today)
        if month != app.calendarMonth {
            forward = month > app.calendarMonth
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.28)) {
                    app.calendarMonth = month
                    app.calendarSelected = today
                }
            }
        } else {
            app.calendarSelected = today
        }
    }
}

// MARK: - Monatsraster

struct MonthGridView: View {
    let month: DayKey
    let selected: DayKey
    let planner: Planner
    let onTap: (DayKey) -> Void
    let onDoubleTap: (DayKey) -> Void

    var body: some View {
        let today = Day.today
        let cells = Day.monthCells(month)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(0..<cells.count, id: \.self) { index in
                if let day = cells[index] {
                    DayCell(day: day,
                            isToday: day == today,
                            isSelected: day == selected,
                            markers: planner.markers(on: day))
                        .onTapGesture(count: 2) { onDoubleTap(day) }
                        .onTapGesture { onTap(day) }
                } else {
                    Color.clear.frame(height: DayCell.height)
                }
            }
        }
        .padding(.horizontal, 8)
    }
}

struct DayCell: View {
    static let height: CGFloat = 52

    let day: DayKey
    let isToday: Bool
    let isSelected: Bool
    let markers: Planner.DayMarkers

    private var dayNumber: Int { Day.components(day).day }
    private var isWeekend: Bool {
        let weekday = Day.weekday(day)
        return weekday == 1 || weekday == 7
    }

    private var textColor: Color {
        if isSelected { return isToday ? .white : Color(uiColor: .systemBackground) }
        if isToday { return Theme.accent }
        return isWeekend ? .secondary : .primary
    }

    private var circleColor: Color {
        if isSelected { return isToday ? Theme.accent : .primary }
        return .clear
    }

    var body: some View {
        VStack(spacing: 3) {
            Text("\(dayNumber)")
                .font(.system(size: 18, weight: (isToday || isSelected) ? .semibold : .regular))
                .foregroundStyle(textColor)
                .frame(width: 36, height: 36)
                .background(Circle().fill(circleColor))

            HStack(spacing: 3) {
                if markers.training {
                    Circle().fill(Theme.accent).frame(width: 5, height: 5)
                }
                if markers.appointment {
                    Circle().fill(Theme.appointment).frame(width: 5, height: 5)
                }
                if markers.task {
                    Circle().fill(Color.secondary.opacity(0.6)).frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: DayCell.height)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Day.fullDate(day))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Übersicht des gewählten Tages

struct DayAgendaView: View {
    let day: DayKey
    let planner: Planner

    /// Termine zuerst (nach Uhrzeit), dann Trainings und To-Dos, dann Gewohnheiten.
    private var sortedRows: [TodoRow] {
        let rows = planner.todoRows(on: day)
        let appointments = rows
            .filter { $0.entryKind == .appointment }
            .sorted { ($0.timeMinutes ?? -1) < ($1.timeMinutes ?? -1) }
        return appointments
            + rows.filter { $0.entryKind == .todo }
            + rows.filter { $0.entryKind == .habit }
    }

    var body: some View {
        let rows = sortedRows

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(Day.fullDate(day))
                    .font(.headline)
                    .padding(.bottom, 8)

                if rows.isEmpty {
                    Text("Keine Einträge")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                }

                ForEach(rows) { row in
                    AgendaRow(row: row)
                    if row.id != rows.last?.id {
                        Divider().padding(.leading, 34)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }
}

struct AgendaRow: View {
    let row: TodoRow

    private var symbol: String {
        if row.isDone { return "checkmark.circle.fill" }
        if row.isTraining { return "dumbbell" }
        switch row.entryKind {
        case .appointment: return "calendar"
        case .habit: return "leaf"
        case .todo: return "circle"
        }
    }

    private var tint: Color {
        if row.isDone { return .secondary }
        return row.entryKind == .appointment ? Theme.appointment : Theme.accent
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .strikethrough(row.isDone, color: .secondary)
                    .foregroundStyle(row.isDone ? Color.secondary : Color.primary)
                if !row.location.isEmpty {
                    Text(row.location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if row.entryKind == .appointment {
                Text(Fmt.timeRange(row.timeMinutes, row.endMinutes))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if let minutes = row.timeMinutes {
                Text(Day.timeString(minutes))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }
}
