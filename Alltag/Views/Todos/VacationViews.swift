import SwiftUI
import SwiftData

/// Eingabefelder für Urlaub – genutzt beim Anlegen (im Eintrags-Editor) und beim Bearbeiten.
struct VacationFormSections: View {
    @Binding var title: String
    @Binding var start: Date
    @Binding var end: Date
    @Binding var pausesTraining: Bool

    private var startKey: DayKey { Day.key(for: start) }
    private var endKey: DayKey { Day.key(for: end) }

    var body: some View {
        Section {
            TextField("Urlaub", text: $title)
        } footer: {
            Text("Optionaler Name, z. B. „Sommerurlaub Italien“.")
        }

        Section {
            DatePicker("Von", selection: $start, displayedComponents: .date)
            DatePicker("Bis", selection: $end, in: start..., displayedComponents: .date)
        } footer: {
            if endKey >= startKey {
                let days = Day.daysBetween(startKey, endKey) + 1
                let workdays = Holidays.workdays(from: startKey, to: endKey)
                Text("\(days == 1 ? "1 Tag" : "\(days) Tage") · \(workdays == 1 ? "1 Arbeitstag" : "\(workdays) Arbeitstage") (Mo–Fr ohne Feiertage)")
            }
        }
        .onChange(of: start) { _, newStart in
            if Day.key(for: end) < Day.key(for: newStart) { end = newStart }
        }

        Section {
            Toggle("Trainings in dieser Zeit aussetzen", isOn: $pausesTraining)
        } footer: {
            Text("Geplante Trainings fallen dann aus. Spontan kannst du trotzdem trainieren.")
        }
    }
}

/// Urlaub anlegen bzw. bestehenden Urlaub bearbeiten oder löschen.
struct VacationEditorView: View {
    let vacation: Vacation?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @State private var pausesTraining: Bool
    @State private var confirmDelete = false

    init(vacation: Vacation?, defaultDay: DayKey = Day.today) {
        self.vacation = vacation
        _title = State(initialValue: vacation?.title ?? "")
        _start = State(initialValue: Day.noon(vacation?.startDay ?? defaultDay))
        _end = State(initialValue: Day.noon(vacation?.endDay ?? Day.adding(6, to: defaultDay)))
        _pausesTraining = State(initialValue: vacation?.pausesTraining ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                VacationFormSections(title: $title, start: $start, end: $end, pausesTraining: $pausesTraining)

                if vacation != nil {
                    Section {
                        Button("Urlaub löschen", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .navigationTitle(vacation == nil ? "Urlaub eintragen" : "Urlaub bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vacation == nil ? "Hinzufügen" : "Sichern") {
                        VacationStore.save(vacation,
                                           title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                           start: Day.key(for: start),
                                           end: Day.key(for: end),
                                           pausesTraining: pausesTraining,
                                           in: ctx)
                        hapticSuccess()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(Day.key(for: end) < Day.key(for: start))
                }
            }
            .confirmationDialog("Urlaub löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    if let vacation {
                        VacationStore.delete(vacation, in: ctx)
                    }
                    dismiss()
                }
                Button("Abbrechen", role: .cancel) {}
            }
        }
    }
}

/// Zeile für einen Urlaub (To-Do-Tab und Einstellungen).
struct VacationRow: View {
    let vacation: Vacation
    /// Wenn gesetzt: „Tag x von y“ für diesen Tag
    var day: DayKey?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.max")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.vacation)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(vacation.displayTitle)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let total = Day.daysBetween(vacation.startDay, vacation.endDay) + 1
        let range = vacation.startDay == vacation.endDay
            ? Day.mediumDate(vacation.startDay)
            : "\(Day.shortDate(vacation.startDay)) – \(Day.mediumDate(vacation.endDay))"
        var parts: [String] = []
        if let day, vacation.contains(day), total > 1 {
            parts.append("Tag \(Day.daysBetween(vacation.startDay, day) + 1) von \(total)")
        } else {
            parts.append(range)
        }
        if vacation.pausesTraining { parts.append("Trainings pausiert") }
        return parts.joined(separator: " · ")
    }
}
