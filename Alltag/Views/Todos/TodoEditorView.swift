import SwiftUI
import SwiftData

/// Auswahl oben im Editor. „Urlaub“ gibt es nur beim Anlegen.
enum EditorKind: String, CaseIterable, Identifiable {
    case todo, appointment, habit, vacation

    var id: String { rawValue }

    var label: String {
        switch self {
        case .todo: return "To-Do"
        case .appointment: return "Termin"
        case .habit: return "Gewohnheit"
        case .vacation: return "Urlaub"
        }
    }

    var entryKind: EntryKind? {
        switch self {
        case .todo: return .todo
        case .appointment: return .appointment
        case .habit: return .habit
        case .vacation: return nil
        }
    }

    init(_ kind: EntryKind) {
        switch kind {
        case .todo: self = .todo
        case .appointment: self = .appointment
        case .habit: self = .habit
        }
    }
}

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
    @State private var hasEndDate: Bool
    @State private var endDate: Date
    @State private var isVacation = false
    @State private var vacationTitle = ""
    @State private var vacationStart: Date
    @State private var vacationEnd: Date
    @State private var vacationPausesTraining = false

    /// Bei „Genaue Daten“ bleibt ein vorhandenes Enddatum (z. B. aus einer Serien-Teilung) erhalten.
    private let originalEndDay: DayKey?

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
            _hasEndDate = State(initialValue: false)
            _endDate = State(initialValue: Day.noon(Day.adding(7, to: day)))
            _vacationStart = State(initialValue: Day.noon(day))
            _vacationEnd = State(initialValue: Day.noon(Day.adding(6, to: day)))
            originalEndDay = nil

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
            let existingEnd: DayKey? = (scope == .single) ? nil : todo.endDay.flatMap { $0 >= start ? $0 : nil }
            _hasEndDate = State(initialValue: existingEnd != nil && todo.repeatKind != .dates)
            _endDate = State(initialValue: Day.noon(existingEnd ?? Day.adding(7, to: start)))
            _vacationStart = State(initialValue: Day.noon(start))
            _vacationEnd = State(initialValue: Day.noon(start))
            originalEndDay = scope == .single ? nil : todo.endDay
        }
    }

    // MARK: - Ableitungen

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var usesEndDate: Bool {
        allowsRepeat && repeatKind != .dates && hasEndDate
    }

    /// Mehrtägiger Termin bzw. To-Do mit Zeitraum
    private var isMultiDay: Bool {
        usesEndDate && repeatKind == .once && Day.key(for: endDate) > Day.key(for: date)
    }

    private var endDateIsInvalid: Bool {
        usesEndDate && Day.key(for: endDate) < Day.key(for: date)
    }

    private var endIsInvalid: Bool {
        kind == .appointment && hasTime && hasEnd && !isMultiDay && Day.minutes(of: endTime) <= Day.minutes(of: time)
    }

    private var isValid: Bool {
        if isVacation { return Day.key(for: vacationEnd) >= Day.key(for: vacationStart) }
        guard !trimmedTitle.isEmpty, !endIsInvalid, !endDateIsInvalid else { return false }
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
                    Picker("Art", selection: editorKind) {
                        ForEach(isNew ? EditorKind.allCases : EditorKind.allCases.filter { $0 != .vacation }) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if isVacation {
                    VacationFormSections(title: $vacationTitle,
                                         start: $vacationStart,
                                         end: $vacationEnd,
                                         pausesTraining: $vacationPausesTraining)
                } else {
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

                if kind != .appointment {
                    Section {
                        Toggle("Wenn nicht erledigt, auf den nächsten Tag verschieben", isOn: $carryOver)
                    } footer: {
                        if carryOver {
                            Text(carryOverHint)
                        }
                    }
                }
                }
            }
            .navigationTitle(isNew ? "Neuer Eintrag" : "\(kind.label) bearbeiten")
            .onChange(of: date) { _, newDate in
                // Enddatum mitziehen, damit es nicht vor dem Start liegt
                if Day.key(for: endDate) < Day.key(for: newDate) { endDate = newDate }
            }
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
                DatePicker(repeatKind == .once ? (isMultiDay ? "Beginnt am" : "Datum") : "Beginnt am",
                           selection: $date,
                           displayedComponents: .date)

                if allowsRepeat {
                    Toggle(endToggleLabel, isOn: $hasEndDate.animation())
                    if hasEndDate {
                        DatePicker(endPickerLabel,
                                   selection: $endDate,
                                   in: date...,
                                   displayedComponents: .date)
                    }
                }
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
            } else if endDateIsInvalid {
                Text("Das Enddatum darf nicht vor dem Startdatum liegen.")
                    .foregroundStyle(.red)
            } else if usesEndDate, let hint = endDateHint {
                Text(hint)
            }
        }
    }

    private var carryOverHint: String {
        guard kind == .habit else {
            return "Das To-Do zeigt an, seit wie vielen Tagen es aufgeschoben wird."
        }
        var text = "Verpasste Tage erscheinen am nächsten Tag zum Nachholen, mit Hinweis, seit wie vielen Tagen. Nachgeholte Tage zählen für deine Serie."
        if repeatKind == .daily {
            text += " Bei täglichen Gewohnheiten kann so jeder verpasste Tag einzeln auftauchen."
        }
        return text
    }

    private var endToggleLabel: String {
        guard repeatKind == .once else { return "Enddatum" }
        switch kind {
        case .appointment: return "Mehrtägig"
        case .todo, .habit: return "Zeitraum"
        }
    }

    private var endPickerLabel: String {
        guard repeatKind == .once else { return "Wiederholen bis" }
        switch kind {
        case .appointment: return "Endet am"
        case .todo, .habit: return "Erledigen bis"
        }
    }

    private var endDateHint: String? {
        let days = Day.daysBetween(Day.key(for: date), Day.key(for: endDate)) + 1
        guard repeatKind == .once else { return "Die Wiederholung endet am \(Day.mediumDate(Day.key(for: endDate)))." }
        guard days > 1 else { return nil }
        switch kind {
        case .appointment: return "Der Termin erscheint an \(days) Tagen."
        case .todo, .habit: return "Das To-Do steht \(days) Tage lang auf deiner Liste, bis du es erledigst."
        }
    }

    private var editorKind: Binding<EditorKind> {
        Binding(
            get: { isVacation ? .vacation : EditorKind(kind) },
            set: { newValue in
                withAnimation {
                    if let entryKind = newValue.entryKind {
                        isVacation = false
                        kind = entryKind
                    } else {
                        isVacation = true
                    }
                }
            }
        )
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
        if isVacation {
            VacationStore.save(nil,
                               title: vacationTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                               start: Day.key(for: vacationStart),
                               end: Day.key(for: vacationEnd),
                               pausesTraining: vacationPausesTraining,
                               in: ctx)
            hapticSuccess()
            dismiss()
            return
        }

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
                              location: location,
                              endDay: draftEndDay(for: effectiveRepeat))

        switch target.mode {
        case .new:
            TodoStore.create(draft, in: ctx)
        case let .edit(todo, origin, scope):
            TodoStore.update(todo, origin: origin, scope: scope, with: draft, in: ctx)
        }
        hapticSuccess()
        dismiss()
    }

    private func draftEndDay(for repeatKind: RepeatKind) -> DayKey? {
        guard allowsRepeat else { return nil }
        if repeatKind == .dates { return originalEndDay }
        return hasEndDate ? Day.key(for: endDate) : nil
    }
}
