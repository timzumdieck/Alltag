import SwiftUI
import SwiftData

// MARK: - Trainingseinheit anlegen / bearbeiten

struct PlanEditorView: View {
    let plan: WorkoutPlan?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Query private var exercises: [Exercise]

    @State private var name: String
    @State private var entries: [PlanEntry]
    @State private var weekdays: Set<Int>
    @State private var specificDays: [DayKey]
    @State private var showPicker = false
    @State private var confirmDelete = false

    init(plan: WorkoutPlan?) {
        self.plan = plan
        _name = State(initialValue: plan?.name ?? "")
        _entries = State(initialValue: plan?.entries ?? [])
        _weekdays = State(initialValue: Set(plan?.currentWeekdays ?? []))
        _specificDays = State(initialValue: plan?.specificDays ?? [])
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func exerciseName(_ id: UUID) -> String {
        exercises.first { $0.id == id }?.name ?? "Übung"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("z. B. Oberkörper A", text: $name)
                        .font(.body)
                } header: {
                    Text("Name")
                }

                Section {
                    ForEach($entries) { $entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exerciseName(entry.exerciseID))
                            Stepper(value: $entry.sets, in: 1...20) {
                                Text(entry.sets == 1 ? "1 Satz" : "\(entry.sets) Sätze")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove { from, to in entries.move(fromOffsets: from, toOffset: to) }
                    .onDelete { offsets in entries.remove(atOffsets: offsets) }

                    Button {
                        showPicker = true
                    } label: {
                        Label("Übung hinzufügen", systemImage: "plus")
                    }
                } header: {
                    Text("Übungen")
                } footer: {
                    Text("Mit den Griffen rechts lässt sich die Reihenfolge ändern.")
                }

                Section {
                    WeekdayPicker(selection: $weekdays)
                } header: {
                    Text("Wiederkehrende Wochentage")
                } footer: {
                    if plan != nil {
                        Text("Änderungen gelten ab heute. Vergangene Trainings bleiben unverändert.")
                    }
                }

                Section {
                    DateListEditor(days: $specificDays)
                } header: {
                    Text("Genaue Daten")
                }

                if plan != nil {
                    Section {
                        Button("Einheit löschen", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(plan == nil ? "Neue Einheit" : "Einheit bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        TrainingStore.savePlan(plan,
                                               name: trimmedName,
                                               entries: entries,
                                               weekdays: Array(weekdays),
                                               specificDays: specificDays,
                                               in: ctx)
                        hapticSuccess()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(trimmedName.isEmpty)
                }
            }
            .sheet(isPresented: $showPicker) {
                ExercisePickerView { exercise in
                    entries.append(PlanEntry(exerciseID: exercise.id, sets: 3))
                }
            }
            .confirmationDialog("Einheit löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    if let plan {
                        TrainingStore.deletePlan(plan, in: ctx)
                    }
                    dismiss()
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Bereits abgeschlossene Trainings bleiben in der Statistik erhalten.")
            }
        }
    }
}

// MARK: - Übung wählen oder neu anlegen

struct ExercisePickerView: View {
    let onPick: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""

    private var trimmed: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filtered: [Exercise] {
        let sorted = exercises.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !trimmed.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private var exactMatchExists: Bool {
        exercises.contains { $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            List {
                if !trimmed.isEmpty && !exactMatchExists {
                    Section {
                        Button {
                            let exercise = TrainingStore.findOrCreateExercise(named: trimmed, in: ctx)
                            onPick(exercise)
                            dismiss()
                        } label: {
                            Label("„\(trimmed)“ neu anlegen", systemImage: "plus.circle")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }

                Section {
                    ForEach(filtered) { exercise in
                        Button {
                            onPick(exercise)
                            dismiss()
                        } label: {
                            Text(exercise.name)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                    }
                }
            }
            .searchable(text: $search,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Übung suchen oder neu anlegen")
            .overlay {
                if exercises.isEmpty && trimmed.isEmpty {
                    EmptyStateView(symbol: "dumbbell",
                                   title: "Noch keine Übungen",
                                   message: "Tippe oben einen Namen ein, um eine Übung anzulegen.")
                }
            }
            .navigationTitle("Übung hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Übersicht aller Einheiten und Übungen

struct PlansListView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \WorkoutPlan.createdAt) private var plans: [WorkoutPlan]
    @Query private var exercises: [Exercise]

    @State private var editing: WorkoutPlan?
    @State private var showNew = false
    @State private var toDelete: WorkoutPlan?

    private var sortedExercises: [Exercise] {
        exercises.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                if plans.isEmpty {
                    Text("Noch keine Einheiten")
                        .foregroundStyle(.secondary)
                }
                ForEach(plans) { plan in
                    Button {
                        editing = plan
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(plan.name)
                                .foregroundStyle(.primary)
                            Text(plan.scheduleSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            toDelete = plan
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
            } header: {
                Text("Trainingseinheiten")
            }

            Section {
                if exercises.isEmpty {
                    Text("Noch keine Übungen")
                        .foregroundStyle(.secondary)
                }
                ForEach(sortedExercises) { exercise in
                    NavigationLink(value: ExerciseRoute(id: exercise.id)) {
                        Text(exercise.name)
                    }
                }
            } header: {
                Text("Übungen & Statistik")
            }
        }
        .navigationTitle("Einheiten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNew = true
                } label: {
                    Image(systemName: "plus")
                        .fontWeight(.light)
                }
            }
        }
        .sheet(item: $editing) { plan in
            PlanEditorView(plan: plan)
        }
        .sheet(isPresented: $showNew) {
            PlanEditorView(plan: nil)
        }
        .confirmationDialog("Einheit löschen?",
                            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible,
                            presenting: toDelete) { plan in
            Button("„\(plan.name)“ löschen", role: .destructive) {
                TrainingStore.deletePlan(plan, in: ctx)
                toDelete = nil
            }
            Button("Abbrechen", role: .cancel) { toDelete = nil }
        } message: { _ in
            Text("Bereits abgeschlossene Trainings bleiben in der Statistik erhalten.")
        }
    }
}
