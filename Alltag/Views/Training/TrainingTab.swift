import SwiftUI
import UIKit
import SwiftData

struct ExerciseRoute: Hashable {
    let id: UUID
}

struct TrainingTab: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var ctx
    @Query(sort: \WorkoutPlan.createdAt) private var plans: [WorkoutPlan]
    @Query private var sessions: [WorkoutSession]

    @State private var selectedSlotID: String?
    @State private var showNewPlan = false
    @State private var showStart = false

    var body: some View {
        @Bindable var app = app
        let planner = Planner(todos: [], completions: [], plans: plans, sessions: sessions)
        let slots = planner.trainings(on: app.trainingDay)

        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    DayNavigator(day: $app.trainingDay)

                    if slots.isEmpty {
                        emptyState
                    } else {
                        if slots.count > 1 {
                            Picker("Einheit", selection: Binding(
                                get: { selectedSlotID ?? slots[0].id },
                                set: { selectedSlotID = $0 })) {
                                ForEach(slots) { slot in
                                    Text(slot.name).tag(slot.id)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        let current = slots.first(where: { $0.id == selectedSlotID }) ?? slots[0]
                        TrainingSessionView(slot: current, allSessions: sessions, onReplace: { showStart = true })
                            .id("\(current.id)|\(app.trainingDay)|\(current.isDone)")

                        Button {
                            showStart = true
                        } label: {
                            Label("Weitere Einheit trainieren", systemImage: "plus.circle")
                                .font(.subheadline)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    }

                    ForEach(planner.skippedPlans(on: app.trainingDay)) { plan in
                        skippedRow(plan, day: app.trainingDay)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Training")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SettingsButton()
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        PlansListView()
                    } label: {
                        Image(systemName: "list.bullet")
                            .fontWeight(.light)
                    }
                    .accessibilityLabel("Einheiten und Übungen")

                    Button {
                        showNewPlan = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.light)
                    }
                    .accessibilityLabel("Neue Trainingseinheit")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { hideKeyboard() }
                }
            }
            .navigationDestination(for: ExerciseRoute.self) { route in
                ExerciseStatsView(exerciseID: route.id)
            }
            .sheet(isPresented: $showNewPlan) {
                PlanEditorView(plan: nil)
            }
            .sheet(isPresented: $showStart) {
                StartTrainingSheet(day: app.trainingDay)
            }
            .onChange(of: app.trainingDay) { _, _ in
                selectedSlotID = nil
            }
        }
    }

    /// Hinweis auf eine für diesen Tag entfernte Einheit – mit Rückgängig-Möglichkeit.
    private func skippedRow(_ plan: WorkoutPlan, day: DayKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.minus")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.name)
                    .font(.subheadline.weight(.medium))
                Text("Für diesen Tag entfernt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Wiederherstellen") {
                TrainingStore.restoreSkipped(plan, day: day, in: ctx)
                haptic(.light)
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.accent)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            EmptyStateView(symbol: "figure.strengthtraining.traditional",
                           title: app.trainingDay == Day.today ? "Heute kein Training" : "Kein Training geplant",
                           message: plans.isEmpty ? "Lege zuerst mit „+“ oben rechts eine Trainingseinheit an." : nil)

            Button {
                if plans.isEmpty { showNewPlan = true } else { showStart = true }
            } label: {
                Text(plans.isEmpty ? "Einheit anlegen" : "Training starten")
                    .font(.headline)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(Theme.accent)
        }
        .padding(.top, 30)
    }
}

// MARK: - Eingabezustand

struct SetInput: Equatable {
    var weight: String = ""
    var reps: String = ""
}

struct ExerciseInput: Equatable, Identifiable {
    var id = UUID()
    var exerciseID: UUID
    var name: String
    var sets: [SetInput]
}

// MARK: - Ein Training mit allen Übungen

struct TrainingSessionView: View {
    let slot: TrainingSlot
    let allSessions: [WorkoutSession]
    let onReplace: () -> Void

    @Environment(\.modelContext) private var ctx
    @Query private var exercises: [Exercise]

    @State private var inputs: [ExerciseInput] = []
    @State private var saved: [ExerciseInput] = []
    @State private var placeholders: [UUID: [SetValue]] = [:]
    @State private var createdSession: WorkoutSession?
    @State private var loaded = false
    @State private var editingPlan: WorkoutPlan?
    @State private var justCompleted = false
    @State private var confirmSkip = false

    private var session: WorkoutSession? {
        if let existing = slot.session { return existing }
        if let created = createdSession, created.modelContext != nil, !created.isDeleted { return created }
        return nil
    }
    private var isCompleted: Bool { session?.isCompleted ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if inputs.isEmpty {
                Text("Diese Einheit enthält noch keine Übungen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
            }

            ForEach($inputs) { $input in
                ExerciseCard(input: $input, placeholders: placeholders[input.exerciseID] ?? [])
            }

            footer
                .padding(.top, 8)
        }
        .onAppear(perform: load)
        .onChange(of: inputs) { _, newValue in
            autosave(newValue)
        }
        .sheet(item: $editingPlan) { plan in
            PlanEditorView(plan: plan)
        }
        .confirmationDialog("Training entfernen?", isPresented: $confirmSkip, titleVisibility: .visible) {
            Button("Nur entfernen", role: .destructive) {
                TrainingStore.skip(slot, in: ctx)
            }
            Button("Durch andere Einheit ersetzen") {
                TrainingStore.skip(slot, in: ctx)
                onReplace()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(slot.isPlanned
                 ? "„\(slot.name)“ entfällt nur am \(Day.mediumDate(slot.day)). An allen anderen Tagen bleibt die Einheit bestehen."
                 : "Das spontane Training „\(slot.name)“ wird entfernt.")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(slot.name)
                    .font(.title2.weight(.semibold))
                if isCompleted {
                    Label("Abgeschlossen", systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                } else if !slot.isPlanned {
                    Text("Spontanes Training")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                if let plan = slot.plan {
                    Button {
                        editingPlan = plan
                    } label: {
                        Label("Einheit bearbeiten", systemImage: "pencil")
                    }
                }
                if isCompleted, let session {
                    Button {
                        session.isCompleted = false
                        session.completedAt = nil
                        session.updatedAt = Date()
                        ctx.commit()
                    } label: {
                        Label("Als nicht erledigt markieren", systemImage: "arrow.uturn.backward")
                    }
                }
                if !isCompleted {
                    Button(role: .destructive) {
                        confirmSkip = true
                    } label: {
                        Label(slot.isPlanned ? "Für diesen Tag entfernen" : "Training entfernen",
                              systemImage: "calendar.badge.minus")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if !isCompleted {
            Button(action: complete) {
                Text("Training abschließen")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .tint(Theme.accent)
        } else {
            VStack(spacing: 12) {
                if inputs != saved {
                    Button(action: saveChanges) {
                        Text("Änderungen speichern")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 16))
                    .tint(Theme.accent)
                }
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolEffect(.bounce, value: justCompleted)
                    Text("Training abgeschlossen")
                }
                .font(.headline)
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Laden & Speichern

    private func load() {
        guard !loaded else { return }
        loaded = true

        var names: [UUID: String] = [:]
        for exercise in exercises { names[exercise.id] = exercise.name }

        var structure: [SessionExercise] = []
        if let session, session.isCompleted || slot.plan == nil {
            structure = session.exercises
        } else if let plan = slot.plan {
            let planned = TrainingStore.structure(for: plan, names: names)
            if let session {
                // Entwurf mit dem aktuellen Plan zusammenführen
                let draft = session.exercises
                structure = planned.enumerated().map { index, entry in
                    var merged = entry
                    let match: SessionExercise?
                    if index < draft.count && draft[index].exerciseID == entry.exerciseID {
                        match = draft[index]
                    } else {
                        match = draft.first { $0.exerciseID == entry.exerciseID }
                    }
                    if let match {
                        var sets = match.sets
                        while sets.count < entry.sets.count { sets.append(SetValue()) }
                        merged.sets = sets
                    }
                    return merged
                }
            } else {
                structure = planned
            }
        }

        let newInputs = structure.map { exercise in
            ExerciseInput(exerciseID: exercise.exerciseID,
                          name: names[exercise.exerciseID] ?? exercise.name,
                          sets: exercise.sets.map { value in
                              SetInput(weight: value.weight.map { Fmt.weight($0) } ?? "",
                                       reps: value.reps.map { String($0) } ?? "")
                          })
        }

        var newPlaceholders: [UUID: [SetValue]] = [:]
        for input in newInputs where newPlaceholders[input.exerciseID] == nil {
            newPlaceholders[input.exerciseID] = TrainingStore.lastSets(exerciseID: input.exerciseID,
                                                                       upTo: slot.day,
                                                                       excluding: session?.id,
                                                                       sessions: allSessions)
        }

        placeholders = newPlaceholders
        saved = newInputs
        inputs = newInputs
    }

    private func sessionExercises(from inputs: [ExerciseInput]) -> [SessionExercise] {
        inputs.map { input in
            SessionExercise(exerciseID: input.exerciseID,
                            name: input.name,
                            sets: input.sets.map { set in
                                SetValue(weight: Fmt.parseDouble(set.weight), reps: Fmt.parseInt(set.reps))
                            })
        }
    }

    private func ensureSession() -> WorkoutSession {
        if let session { return session }
        let newSession = WorkoutSession(day: slot.day, planID: slot.plan?.id, planName: slot.name)
        ctx.insert(newSession)
        createdSession = newSession
        return newSession
    }

    /// Eingaben werden laufend als Entwurf gesichert, damit beim Tab-Wechsel nichts verloren geht.
    private func autosave(_ value: [ExerciseInput]) {
        guard loaded, value != saved, !isCompleted else { return }
        let target = ensureSession()
        target.exercises = sessionExercises(from: value)
        target.updatedAt = Date()
        try? ctx.save()
        saved = value
    }

    private func complete() {
        hideKeyboard()
        let target = ensureSession()
        target.exercises = sessionExercises(from: inputs)
        target.isCompleted = true
        target.completedAt = Date()
        target.updatedAt = Date()
        saved = inputs
        ctx.commit()
        hapticSuccess()
        justCompleted.toggle()
    }

    private func saveChanges() {
        hideKeyboard()
        guard let session else { return }
        session.exercises = sessionExercises(from: inputs)
        session.updatedAt = Date()
        saved = inputs
        ctx.commit()
        hapticSuccess()
    }
}

// MARK: - Karte einer Übung

struct ExerciseCard: View {
    @Binding var input: ExerciseInput
    let placeholders: [SetValue]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: ExerciseRoute(id: input.exerciseID)) {
                HStack(spacing: 6) {
                    Text(input.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.footnote.weight(.light))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.light))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Text("Satz").frame(width: 36, alignment: .leading)
                Text("kg").frame(maxWidth: .infinity)
                Text("Wdh.").frame(maxWidth: .infinity)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach(input.sets.indices, id: \.self) { index in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .leading)
                    NumberField(text: $input.sets[index].weight,
                                placeholder: weightPlaceholder(index),
                                keyboard: .decimalPad)
                    NumberField(text: $input.sets[index].reps,
                                placeholder: repsPlaceholder(index),
                                keyboard: .numberPad)
                }
            }

            Button {
                input.sets.append(SetInput())
            } label: {
                Label("Satz hinzufügen", systemImage: "plus")
                    .font(.footnote)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.card)
        )
    }

    private func weightPlaceholder(_ index: Int) -> String {
        guard index < placeholders.count, let weight = placeholders[index].weight else { return "–" }
        return Fmt.weight(weight)
    }

    private func repsPlaceholder(_ index: Int) -> String {
        guard index < placeholders.count, let reps = placeholders[index].reps else { return "–" }
        return String(reps)
    }
}

// MARK: - Spontanes Training starten

struct StartTrainingSheet: View {
    let day: DayKey
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Query(sort: \WorkoutPlan.createdAt) private var plans: [WorkoutPlan]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(plans) { plan in
                        Button {
                            TrainingStore.startSpontaneous(plan, day: day, in: ctx)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(plan.name)
                                    .foregroundStyle(.primary)
                                Text(plan.entries.count == 1 ? "1 Übung" : "\(plan.entries.count) Übungen")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } footer: {
                    Text("Das Training wird am \(Day.mediumDate(day)) eingetragen.")
                }
            }
            .overlay {
                if plans.isEmpty {
                    EmptyStateView(symbol: "dumbbell", title: "Noch keine Einheiten", message: "Lege zuerst eine Trainingseinheit an.")
                }
            }
            .navigationTitle("Training starten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
