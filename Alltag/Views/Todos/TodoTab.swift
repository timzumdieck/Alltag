import SwiftUI
import UIKit
import SwiftData

struct TodoEditorTarget: Identifiable {
    enum Mode {
        case new(DayKey)
        case edit(TodoItem, DayKey, EditScope)
    }

    let id = UUID()
    let mode: Mode
}

private struct SeriesAction: Identifiable {
    let id = UUID()
    let todo: TodoItem
    let origin: DayKey
    let isDelete: Bool
}

struct TodoTab: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var ctx

    @Query private var todos: [TodoItem]
    @Query private var completions: [TodoCompletion]
    @Query private var plans: [WorkoutPlan]
    @Query private var sessions: [WorkoutSession]

    @State private var editorTarget: TodoEditorTarget?
    @State private var seriesAction: SeriesAction?
    @State private var skipSlot: TrainingSlot?
    @State private var replacementDay: DayKey?

    var body: some View {
        @Bindable var app = app
        let planner = Planner(todos: todos, completions: completions, plans: plans, sessions: sessions)
        let rows = planner.todoRows(on: app.todoDay, includeStreaks: true)
        let appointments = rows
            .filter { $0.entryKind == .appointment }
            .sorted { ($0.timeMinutes ?? -1) < ($1.timeMinutes ?? -1) }
        let tasks = rows.filter { $0.entryKind == .todo }
        let habits = rows.filter { $0.entryKind == .habit }
        let checkable = tasks + habits
        let openCount = checkable.filter { !$0.isDone }.count

        NavigationStack {
            VStack(spacing: 0) {
                DayNavigator(day: $app.todoDay)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                if !checkable.isEmpty {
                    Text(openCount == 0 ? "Alles erledigt" : "\(openCount) offen · \(checkable.count - openCount) erledigt")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                        .contentTransition(.numericText())
                }

                List {
                    section(.appointment, rows: appointments)
                    section(.todo, rows: tasks)
                    section(.habit, rows: habits)
                }
                .listStyle(.plain)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: rows.map { $0.signature })
                .overlay {
                    if rows.isEmpty {
                        EmptyStateView(symbol: "checkmark.circle",
                                       title: "Nichts geplant",
                                       message: "Mit „+“ oben rechts legst du ein To-Do, einen Termin oder eine Gewohnheit an.")
                    }
                }
                .confirmationDialog("Training entfernen?",
                                    isPresented: Binding(get: { skipSlot != nil }, set: { if !$0 { skipSlot = nil } }),
                                    titleVisibility: .visible,
                                    presenting: skipSlot) { slot in
                    Button("Nur entfernen", role: .destructive) {
                        TrainingStore.skip(slot, in: ctx)
                    }
                    Button("Durch andere Einheit ersetzen") {
                        TrainingStore.skip(slot, in: ctx)
                        replacementDay = slot.day
                    }
                    Button("Abbrechen", role: .cancel) {}
                } message: { slot in
                    Text(slot.isPlanned
                         ? "„\(slot.name)“ entfällt nur am \(Day.mediumDate(slot.day)). An allen anderen Tagen bleibt die Einheit bestehen."
                         : "Das spontane Training „\(slot.name)“ wird entfernt.")
                }
                .sheet(isPresented: Binding(get: { replacementDay != nil }, set: { if !$0 { replacementDay = nil } })) {
                    StartTrainingSheet(day: replacementDay ?? app.todoDay)
                }
            }
            .navigationTitle("To-Dos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SettingsButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorTarget = TodoEditorTarget(mode: .new(app.todoDay))
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.light)
                    }
                    .accessibilityLabel("Neuer Eintrag")
                }
            }
            .sheet(item: $editorTarget) { target in
                TodoEditorView(target: target)
            }
            .confirmationDialog(seriesAction?.isDelete == true ? "Wiederkehrenden Eintrag löschen" : "Wiederkehrenden Eintrag bearbeiten",
                                isPresented: Binding(get: { seriesAction != nil }, set: { if !$0 { seriesAction = nil } }),
                                titleVisibility: .visible,
                                presenting: seriesAction) { action in
                if action.isDelete {
                    Button("Nur dieses löschen", role: .destructive) {
                        TodoStore.delete(action.todo, origin: action.origin, scope: .single, in: ctx)
                    }
                    Button("Alle zukünftigen löschen", role: .destructive) {
                        TodoStore.delete(action.todo, origin: action.origin, scope: .future, in: ctx)
                    }
                } else {
                    Button("Nur dieses bearbeiten") {
                        editorTarget = TodoEditorTarget(mode: .edit(action.todo, action.origin, .single))
                    }
                    Button("Alle zukünftigen bearbeiten") {
                        editorTarget = TodoEditorTarget(mode: .edit(action.todo, action.origin, .future))
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            }
        }
    }

    // MARK: - Abschnitte

    @ViewBuilder
    private func section(_ kind: EntryKind, rows: [TodoRow]) -> some View {
        if !rows.isEmpty {
            Section {
                ForEach(rows) { row in
                    rowView(row)
                }
            } header: {
                Label(kind.sectionTitle, systemImage: kind.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(kind == .appointment ? Theme.appointment : Theme.accent)
                    .labelStyle(.titleAndIcon)
                    .textCase(nil)
            }
        }
    }

    private func rowView(_ row: TodoRow) -> some View {
        TodoRowView(row: row)
            .contentShape(Rectangle())
            .onTapGesture { tap(row) }
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                swipeButtons(for: row)
            }
            .contextMenu {
                contextMenu(for: row)
            }
    }

    @ViewBuilder
    private func swipeButtons(for row: TodoRow) -> some View {
        if let ref = row.todoRef {
            Button {
                requestDelete(ref.todo, origin: ref.origin)
            } label: {
                Label("Löschen", systemImage: "trash")
            }
            .tint(.red)

            Button {
                requestEdit(ref.todo, origin: ref.origin)
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }
            .tint(.gray)
        } else if let slot = row.trainingSlot, !slot.isDone {
            Button {
                skipSlot = slot
            } label: {
                Label("Entfernen", systemImage: "calendar.badge.minus")
            }
            .tint(.orange)
        }
    }

    @ViewBuilder
    private func contextMenu(for row: TodoRow) -> some View {
        if let ref = row.todoRef {
            Button {
                requestEdit(ref.todo, origin: ref.origin)
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }
            Button(role: .destructive) {
                requestDelete(ref.todo, origin: ref.origin)
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        } else if let slot = row.trainingSlot {
            Button {
                app.open(.training, day: slot.day)
            } label: {
                Label("Training öffnen", systemImage: "dumbbell")
            }
            if !slot.isDone {
                Button(role: .destructive) {
                    skipSlot = slot
                } label: {
                    Label("Für diesen Tag entfernen", systemImage: "calendar.badge.minus")
                }
            }
        }
    }

    // MARK: - Aktionen

    private func tap(_ row: TodoRow) {
        if row.entryKind == .appointment {
            if let ref = row.todoRef { requestEdit(ref.todo, origin: ref.origin) }
            return
        }
        haptic(.light)
        if let ref = row.todoRef {
            TodoStore.toggle(ref.todo, origin: ref.origin, in: ctx)
        } else if let slot = row.trainingSlot {
            TrainingStore.toggle(slot, in: ctx)
        }
    }

    private func requestEdit(_ todo: TodoItem, origin: DayKey) {
        if todo.isRecurring {
            seriesAction = SeriesAction(todo: todo, origin: origin, isDelete: false)
        } else {
            editorTarget = TodoEditorTarget(mode: .edit(todo, origin, .all))
        }
    }

    private func requestDelete(_ todo: TodoItem, origin: DayKey) {
        if todo.isRecurring {
            seriesAction = SeriesAction(todo: todo, origin: origin, isDelete: true)
        } else {
            TodoStore.delete(todo, origin: origin, scope: .all, in: ctx)
        }
    }
}

// MARK: - Zeile

struct TodoRowView: View {
    let row: TodoRow

    var body: some View {
        if row.entryKind == .appointment {
            appointmentRow
        } else {
            checkRow
        }
    }

    /// Termin: Uhrzeit links, farbiger Balken, kein Abhaken.
    private var appointmentRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                if let start = row.timeMinutes {
                    Text(Day.timeString(start))
                        .font(.subheadline.weight(.medium).monospacedDigit())
                    if let end = row.endMinutes {
                        Text(Day.timeString(end))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("ganztägig")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 58, alignment: .trailing)

            RoundedRectangle(cornerRadius: 1.5)
                .fill(Theme.appointment)
                .frame(width: 3, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.body)
                if !row.location.isEmpty || row.isRecurring {
                    HStack(spacing: 10) {
                        if !row.location.isEmpty {
                            Label(row.location, systemImage: "mappin")
                        }
                        if row.isRecurring {
                            Image(systemName: "repeat")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .imageScale(.small)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    /// To-Do, Gewohnheit oder Training: zum Abhaken.
    private var checkRow: some View {
        HStack(spacing: 14) {
            Image(systemName: row.isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(row.isDone ? Color.secondary : Theme.accent)
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.body)
                    .strikethrough(row.isDone, color: .secondary)
                    .foregroundStyle(row.isDone ? Color.secondary : Color.primary)

                if hasDetails {
                    HStack(spacing: 10) {
                        if row.isTraining {
                            Label("Training", systemImage: "dumbbell")
                        }
                        if let minutes = row.timeMinutes {
                            Label(Day.timeString(minutes), systemImage: "clock")
                        }
                        if let from = row.carriedFrom {
                            Label("von \(Day.shortDate(from))", systemImage: "arrow.turn.down.right")
                        }
                        if row.entryKind == .habit && row.streak >= 2 {
                            Label("\(row.streak)× in Folge", systemImage: "flame")
                        }
                        if row.entryKind == .todo && row.isRecurring && !row.isTraining {
                            Image(systemName: "repeat")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .imageScale(.small)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .opacity(row.isDone ? 0.65 : 1)
    }

    private var hasDetails: Bool {
        row.isTraining
            || row.timeMinutes != nil
            || row.carriedFrom != nil
            || (row.entryKind == .habit && row.streak >= 2)
            || (row.entryKind == .todo && row.isRecurring)
    }
}
