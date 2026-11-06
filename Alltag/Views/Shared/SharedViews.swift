import SwiftUI
import UIKit

/// Kopfzeile zum Wechseln des Tages: ‹  Heute / 6. November 2026  ›
struct DayNavigator: View {
    @Binding var day: DayKey
    @State private var showPicker = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                arrow("chevron.left", label: "Vorheriger Tag") { day = Day.adding(-1, to: day) }

                Button {
                    showPicker = true
                } label: {
                    VStack(spacing: 2) {
                        Text(Day.relativeTitle(day))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(Day.longDate(day))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)

                arrow("chevron.right", label: "Nächster Tag") { day = Day.adding(1, to: day) }
            }

            if day != Day.today {
                Button("Zu heute") {
                    day = Day.today
                }
                .font(.footnote.weight(.medium))
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.accent)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: day)
        .sheet(isPresented: $showPicker) {
            DayPickerSheet(day: $day)
        }
    }

    private func arrow(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            haptic(.soft)
            action()
        }) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .light))
                .frame(width: 50, height: 50)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.accent)
        .accessibilityLabel(label)
    }
}

struct DayPickerSheet: View {
    @Binding var day: DayKey
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("Datum",
                           selection: Binding(get: { Day.noon(day) }, set: { day = Day.key(for: $0) }),
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding(.horizontal)
                Spacer(minLength: 0)
            }
                .navigationTitle("Tag wählen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Heute") {
                            day = Day.today
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }
                    }
                }
        }
        .presentationDetents([.large])
    }
}

/// Sieben runde Schalter Mo–So.
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Day.weekdayOrder, id: \.self) { weekday in
                let isOn = selection.contains(weekday)
                Button {
                    if isOn { selection.remove(weekday) } else { selection.insert(weekday) }
                    haptic(.soft)
                } label: {
                    Text(Day.shortWeekdayName(weekday))
                        .font(.subheadline.weight(isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(isOn ? Theme.accent : Theme.field))
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

/// Liste genauer Daten mit Hinzufügen/Entfernen (für Form-Sections).
struct DateListEditor: View {
    @Binding var days: [DayKey]
    @State private var newDate = Date()

    var body: some View {
        ForEach(days.sorted(), id: \.self) { day in
            HStack {
                Text(Day.mediumDate(day))
                Spacer()
                Button {
                    days.removeAll { $0 == day }
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Datum entfernen")
            }
        }
        HStack {
            DatePicker("Datum", selection: $newDate, displayedComponents: .date)
                .labelsHidden()
            Spacer()
            Button {
                let key = Day.key(for: newDate)
                if !days.contains(key) { days.append(key) }
                haptic(.soft)
            } label: {
                Label("Hinzufügen", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }
}

/// Zahlenfeld mit großer Tippfläche und Ziffern-Tastatur.
struct NumberField: View {
    @Binding var text: String
    let placeholder: String
    let keyboard: UIKeyboardType
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .font(.body.monospacedDigit())
            .focused($focused)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.field)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(focused ? Theme.accent : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
    }
}

/// Leerer Zustand mit Symbol und Text.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.title3.weight(.medium))
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
