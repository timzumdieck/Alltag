import SwiftUI
import SwiftData

struct TodoEditorView: View {
    let target: TodoEditorTarget

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    @State private var kind: EntryKind
    @State private var title: String
    @State private var location: String
    @State private var date: Date
    @State private var hasTime: Bool
    @State private var time: Date
    @State private var hasEnd: Bool
    @State private var endTime: Date
    @State private var repeatKind: RepeatKind
    @State private var weekdays: Set<Int>
    @State private var dates: [DayKey]
    @State private var hasReminder: Bool
    @State private var reminderTime: Date
    @State private var reminderOffset: Int?
    @State private var carryOver: Bool

    private let isNew: Bool
    private let allowsRepeat: Bool

    init(target: TodoEditorTarget) {
        self.target = target

        switch target.mode {
        case let .new(day):
            isNew = true
            allowsRepeat = true
            _kind = State(initialValue: .todo)
            _title = State(initialValue: "")
            _location = State(initialValue: "")
            _date = State(initialValue: Day.noon(day))
            _hasTime = State(initialValue: false)
            _time = State(initialValue: Day.date(Day.today, minutes: 9 * 60))
            _hasEnd = State(initialValue: false)
            _endTime = State(initialValue: Day.date(Day.today, minutes: 10 * 60))
            _repeatKind = State(initialValue: .once)
            _weekdays = State(initialValue: [Day.weekday(day)])
            _dates = State(initialValue: [day])
            _hasReminder = State(initialValue: false)
            _reminderTime = State(initialValue: Day.date(Day.today, minutes: 9 * 60))
            _reminderOffset = State(initialValue: nil)
            _carryOver = State(initialValue: false)

        case let .edit(todo, origin, scope):
            isNew = false
            allowsRepeat = scope != .single
            let start: DayKey
            switch scope {
            case .all: start = todo.startDay
            case .single, .future: start = origin
            }
            let startMinutes = todo.timeMinutes ?? 9 * 60
            _kind = State(initialValue: todo.entryKind)
            _title = State(initialValue: todo.title)
            _location = State(initialValue: todo.location)
            _date = State(initialValue: Day.noon(start))
            _hasTime = State(initialValue: todo.timeMinutes != nil)
            _time = State(initialValue: Day.date(Day.today, minutes: startMinutes))
            _hasEnd = State(initialValue: todo.endMinutes != nil)
            _endTime = State(initialValue: Day.date(Day.today, minutes: todo.endMinutes ?? min(startMinutes + 60, 23 * 60 + 59)))
            _repeatKind = State(initialValue: scope == .single ? .once : todo.repeatKind)
            _weekdays = State(initialValue: Set(todo.weekdays.isEmpty ? [Day.weekday(start)] : todo.weekdays))
            let existingDates = scope == .future ? todo.dates.filter { $0 >= origin } : todo.dates
            _dates = State(initialValue: existingDates.isEmpty ? [start] : existingDates)
            _hasReminder = State(initialValue: todo.reminderMinutes != nil)
            _reminderTime = State(initialValue: Day.date(Day.today, minutes: todo.reminderMinutes ?? startMinutes))
            _reminderOffset = State(initialValue: todo.reminderOffset)
            _carryOver = State(initialValue: todo.carryOver)
        }
    }

    // MARK: - Ableitungen

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var endIsInvalid: Bool {
        kind == .appointment && hasTime && hasEnd && Day.minutes(of: endTime) <= Day.minutes(of: time)
    }

    private var isValid: Bool {
        guard !trimmedTitle.isEmpty, !endIsInvalid else { return false }
        switch repeatKind {
        case .weekdays: return !weekdays.isEmpty
        case .dates: return !dates.isEmpty
        case .once, .daily: return true
        }
    }

    private var repeatOptions: [RepeatKind] {
        kind == .habit ? RepeatKind.allCases.filter { $0 != .once } : RepeatKind.allCases
    }

    private var titlePlaceholder: String {
        switch kind {
        case .todo: return "Was ist zu tun?"
        case .appointment: return "Titel des Termins"
        case .habit: return "z. B. 10 Minuten lesen"
        }
    }

    // MARK: - Ansicht

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Art", selection: $kind.animation()) {
                        ForEach(EntryKind.allCases) { entryKind in
                            Text(entryKind.label).tag(entryKind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    TextField(titlePlaceholder, text: $title, axis: .vertical)
                    if kind == .appointment {
                        TextField("Ort (optional)", text: $location)
                    }
                }

                dateSection

                if allowsRepeat {
                    Section {
                        Picker("Wiederholung", selection: $repeatKind.animation()) {
                            ForEach(repeatOptions) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        if repeatKind == .weekdays {
                            WeekdayPicker(selection: $weekdays)
                        }
                    } header: {
                        Text("Wiederholung")
                    }

                    if repeatKind == .dates {
                        Section {
                            DateListEditor(days: $dates)
                        } header: {
                            Text("Genaue Daten")
                        }
                    }
                }

                reminderSection

                if kind == .todo {
                    Section {
                        Toggle("Wenn nicht erledigt, auf den nächsten Tag verschieben", isOn: $carryOver)
                    }
                }
            }
            .navigationTitle(isNew ? "Neuer Eintrag" : "\(kind.label) bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Hinzufügen" : "Sichern", action: save)
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                }
            }
            .onChange(of: kind) { _, newKind in
                if newKind == .habit && repeatKind == .once {
                    repeatKind = .daily
                }
                if newKind == .appointment && isNew && !hasTime {
                    hasTime = true
                }
            }
        }
    }

    @ViewBuilder
    private var dateSection: some View {
        Section {
            if repeatKind != .dates {
                DatePicker(repeatKind == .once ? "Datum" : "Beginnt am",
                           selection: $date,
                           displayedComponents: .date)
            }

            if kind == .appointment {
                Toggle("Ganztägig", isOn: Binding(get: { !hasTime }, set: { hasTime = !$0 }).animation())
                if hasTime {
                    DatePicker("Beginn", selection: $time, displayedComponents: .hourAndMinute)
                    Toggle("Ende", isOn: $hasEnd.animation())
                    if hasEnd {
                        DatePicker("Ende", selection: $endTime, displayedComponents: .hourAndMinute)
                    }
                }
            } else {
                Toggle("Uhrzeit", isOn: $hasTime.animation())
                if hasTime {
                    DatePicker("Uhrzeit", selection: $time, displayedComponents: .hourAndMinute)
                }
            }
        } footer: {
            if endIsInvalid {
                Text("Das Ende muss nach dem Beginn liegen.")
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var reminderSection: some View {
        if kind == .appointment {
            Section {
                Picker("Erinnerung", selection: $reminderOffset) {
                    Text("Keine").tag(Int?.none)
                    ForEach(Fmt.reminderOffsets, id: \.self) { offset in
                        Text(Fmt.offsetLabel(offset)).tag(Int?.some(offset))
                    }
                }
            } footer: {
                if !hasTime && reminderOffset != nil {
                    Text("Bei ganztägigen Terminen wird von 9:00 Uhr aus gerechnet.")
                }
            }
        } else {
            Section {
                Toggle("Erinnerung", isOn: $hasReminder.animation())
                if hasReminder {
                    DatePicker("Zeitpunkt", selection: $reminderTime, displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("Die Erinnerung kommt am jeweiligen Tag zur gewählten Uhrzeit.")
            }
        }
    }

    // MARK: - Speichern

    private func save() {
        let effectiveRepeat: RepeatKind
        if !allowsRepeat {
            effectiveRepeat = .once
        } else if kind == .habit && repeatKind == .once {
            effectiveRepeat = .daily
        } else {
            effectiveRepeat = repeatKind
        }

        let draft = TodoDraft(kind: kind,
                              title: trimmedTitle,
                              startDay: Day.key(for: date),
                              timeMinutes: hasTime ? Day.minutes(of: time) : nil,
                              repeatKind: effectiveRepeat,
                              weekdays: Array(weekdays),
                              dates: dates,
                              reminderMinutes: hasReminder ? Day.minutes(of: reminderTime) : nil,
                              carryOver: carryOver,
                              endMinutes: (hasTime && hasEnd) ? Day.minutes(of: endTime) : nil,
                              reminderOffset: reminderOffset,
                              location: location)

        switch target.mode {
        case .new:
            TodoStore.create(draft, in: ctx)
        case let .edit(todo, origin, scope):
            TodoStore.update(todo, origin: origin, scope: scope, with: draft, in: ctx)
        }
        hapticSuccess()
        dismiss()
    }
}
