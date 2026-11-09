import SwiftUI
import SwiftData
import Charts

// Fortschritt einer Übung.
//
// Aufbau (von oben nach unten):
// 1. Zeitraum (3 M / 6 M / 1 J / Alle) – gilt für alles darunter
// 2. Kraftentwicklung: geschätztes 1RM als große Zahl + Veränderung + Verlaufslinie mit Rekorden
//    (ohne Gewicht: beste Serie in Wiederholungen)
// 3. Kacheln: letzte Einheit, Volumen
// 4. Gewicht: schwerster Satz als Linie, alle Sätze als graue Punkte dahinter
// 5. Wiederholungen und Volumen pro Einheit als gestapelte Balken – Höhe = Summe, Segmente = Sätze
// 6. Rekorde und Verlauf

struct ExerciseStatsView: View {
    let exerciseID: UUID

    @Environment(\.modelContext) private var ctx
    @Query private var sessions: [WorkoutSession]
    @Query private var exercises: [Exercise]

    @State private var range: StatRange = .all
    @State private var showRename = false
    @State private var renameText = ""

    private var exercise: Exercise? {
        exercises.first { $0.id == exerciseID }
    }

    var body: some View {
        let allDays = ExerciseStats.days(for: exerciseID, sessions: sessions)
        let days = ExerciseStats.filter(allDays, range: range)
        let usesWeight = allDays.contains { $0.oneRepMax != nil }

        ScrollView {
            VStack(spacing: 16) {
                if allDays.isEmpty {
                    EmptyStateView(symbol: "chart.xyaxis.line",
                                   title: "Noch keine Daten",
                                   message: "Schließe ein Training mit dieser Übung ab, um hier deinen Fortschritt zu sehen.")
                } else {
                    Picker("Zeitraum", selection: $range) {
                        ForEach(StatRange.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    if days.isEmpty {
                        EmptyStateView(symbol: "calendar",
                                       title: "Keine Einheiten im Zeitraum",
                                       message: "Wähle einen längeren Zeitraum.")
                    } else {
                        StrengthCard(days: days, range: range, usesWeight: usesWeight)

                        HStack(alignment: .top, spacing: 12) {
                            LastSessionTile(day: days[days.count - 1], usesWeight: usesWeight)
                            if usesWeight {
                                VolumeTile(days: days)
                            } else {
                                SessionsTile(days: days, range: range)
                            }
                        }

                        if usesWeight {
                            WeightCard(days: days, range: range)
                        }

                        SetStackCard(title: "Wiederholungen pro Einheit",
                                     subtitle: "Höhe = alle Wiederholungen, Segmente = einzelne Sätze",
                                     metric: .reps,
                                     days: days)

                        if usesWeight && days.contains(where: { $0.volume > 0 }) {
                            SetStackCard(title: "Volumen pro Einheit",
                                         subtitle: "Gewicht × Wiederholungen, in kg",
                                         metric: .volume,
                                         days: days)
                        }
                    }

                    RecordsCard(records: ExerciseStats.records(allDays))
                    HistoryCard(days: allDays)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle(exercise?.name ?? "Übung")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    renameText = exercise?.name ?? ""
                    showRename = true
                } label: {
                    Image(systemName: "pencil")
                        .fontWeight(.light)
                }
                .accessibilityLabel("Übung umbenennen")
                .disabled(exercise == nil)
            }
        }
        .alert("Übung umbenennen", isPresented: $showRename) {
            TextField("Name", text: $renameText)
            Button("Abbrechen", role: .cancel) {}
            Button("Sichern") {
                if let exercise {
                    TrainingStore.renameExercise(exercise, to: renameText, in: ctx)
                }
            }
        }
    }
}

// MARK: - Gemeinsame Bausteine

private struct StatCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
    }
}

private struct CardHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Veränderung mit Pfeil – Richtung nie nur über die Farbe.
private struct DeltaLabel: View {
    let delta: Double
    let unit: String
    let suffix: String
    var compact = false

    var body: some View {
        let isUp = delta > 0.05
        let isDown = delta < -0.05
        HStack(spacing: 4) {
            Image(systemName: isUp ? "arrow.up.right" : (isDown ? "arrow.down.right" : "arrow.right"))
                .font(.caption.weight(.semibold))
            Text("\(Fmt.signed(delta, compact: compact)) \(unit)")
                .font(.subheadline.weight(.semibold))
            Text(suffix)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(isUp ? Theme.accent : (isDown ? Theme.holiday : Color.secondary))
    }
}

/// Kleiner Hinweis, der beim Antippen/Ziehen über einem Diagramm erscheint.
private struct ChartTooltip: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        )
    }
}

private enum ChartScale {
    /// Wertebereich mit Luft nach oben und unten (Linien beginnen nicht bei 0).
    static func padded(_ values: [Double]) -> ClosedRange<Double> {
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let span = max(high - low, max(high * 0.1, 2.5))
        let lower = max(0, low - span * 0.3)
        let upper = high + span * 0.3
        return lower...upper
    }

    /// Zeitachse: beim Zeitraum vom Beginn des Zeitraums bis heute, bei „Alle“ von der ersten bis zur letzten Einheit.
    static func dates(_ days: [ExerciseDayStat], range: StatRange) -> ClosedRange<Date> {
        let first = days.first?.date ?? Date()
        let last = days.last?.date ?? Date()
        var start = range.startDay.map { Day.noon($0) } ?? first
        var end = range == .all ? last : max(last, Day.noon(Day.today))
        if end.timeIntervalSince(start) < 6 * 86_400 {
            start = start.addingTimeInterval(-3 * 86_400)
            end = end.addingTimeInterval(3 * 86_400)
        }
        return start...end
    }

    static func nearest(_ days: [ExerciseDayStat], to date: Date?) -> ExerciseDayStat? {
        guard let date else { return nil }
        return days.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

// MARK: - Kraftentwicklung (Hauptdiagramm)

private struct StrengthCard: View {
    let days: [ExerciseDayStat]
    let range: StatRange
    let usesWeight: Bool

    @State private var selectedDate: Date?

    private struct Point: Identifiable {
        let id: DayKey
        let date: Date
        let value: Double
        let isRecord: Bool
        let detail: String
    }

    private var points: [Point] {
        days.compactMap { day in
            if usesWeight {
                guard let value = day.oneRepMax else { return nil }
                return Point(id: day.day, date: day.date, value: value, isRecord: day.isRecord,
                             detail: day.bestSet.map { "Bester Satz \(Fmt.setText($0))" } ?? "")
            }
            guard let reps = day.maxReps else { return nil }
            return Point(id: day.day, date: day.date, value: Double(reps), isRecord: day.isRecord,
                         detail: "\(day.totalReps) Wdh. insgesamt")
        }
    }

    private var unit: String { usesWeight ? "kg" : "Wdh." }

    private func format(_ value: Double) -> String {
        usesWeight ? Fmt.weight(value.rounded(toStep: 0.5)) : String(Int(value.rounded()))
    }

    var body: some View {
        let points = self.points
        let domain = ChartScale.padded(points.map { $0.value })
        let xDomain = ChartScale.dates(days, range: range)
        let selected = selectedDate.flatMap { date in
            points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }

        StatCard {
            CardHeader(title: usesWeight ? "Geschätztes 1RM" : "Beste Serie",
                       subtitle: usesWeight
                           ? "Maximalgewicht für eine Wiederholung, berechnet aus deinem besten Satz"
                           : "Meiste Wiederholungen in einem Satz")

            if let last = points.last {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(format(last.value)) \(unit)")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.primary)
                    if let first = points.first, points.count > 1 {
                        let percent = first.value > 0 ? (last.value - first.value) / first.value * 100 : 0
                        DeltaLabel(delta: last.value - first.value,
                                   unit: unit,
                                   suffix: "(\(Fmt.signed(percent, compact: true)) %) seit \(Day.shortDate(first.id))")
                    } else {
                        Text("Erste Einheit – ab der nächsten siehst du deine Entwicklung.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value("Datum", point.date),
                             yStart: .value("Basis", domain.lowerBound),
                             yEnd: .value("Wert", point.value))
                        .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.16), Theme.accent.opacity(0.0)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)

                    LineMark(x: .value("Datum", point.date),
                             y: .value("Wert", point.value))
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }

                // Rekorde: gefüllter Punkt mit Ring in Kartenfarbe
                ForEach(points.filter { $0.isRecord || $0.id == points.last?.id }) { point in
                    PointMark(x: .value("Datum", point.date), y: .value("Wert", point.value))
                        .symbolSize(130)
                        .foregroundStyle(Theme.card)
                    PointMark(x: .value("Datum", point.date), y: .value("Wert", point.value))
                        .symbolSize(point.isRecord ? 60 : 40)
                        .foregroundStyle(Theme.accent)
                }

                if let selected {
                    RuleMark(x: .value("Datum", selected.date))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .annotation(position: .top, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            ChartTooltip(title: Day.mediumDate(selected.id),
                                         lines: ["\(format(selected.value)) \(unit)\(selected.isRecord ? " · Rekord" : "")",
                                                 selected.detail].filter { !$0.isEmpty })
                        }
                }
            }
            .chartYScale(domain: domain)
            .chartXScale(domain: xDomain)
            .chartXSelection(value: $selectedDate)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(usesWeight ? Fmt.weight(number) : String(Int(number)))
                        }
                    }
                }
            }
            .frame(height: 210)
            .padding(.top, 8)

            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 8, height: 8)
                Text("Neuer Rekord · Tippen und ziehen für Details")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Kacheln

private struct LastSessionTile: View {
    let day: ExerciseDayStat
    let usesWeight: Bool

    var body: some View {
        StatCard {
            Text("Letzte Einheit")
                .font(.caption)
                .foregroundStyle(.secondary)
            if usesWeight, let best = day.bestSet {
                Text(Fmt.setText(best))
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("bester Satz · \(Day.relativeOrShort(day.day))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(day.totalReps) Wdh.")
                    .font(.title3.weight(.semibold))
                Text("\(day.sets.count) Sätze · \(Day.relativeOrShort(day.day))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct VolumeTile: View {
    let days: [ExerciseDayStat]

    var body: some View {
        let last = days[days.count - 1]
        let previous = days.count > 1 ? days[days.count - 2] : nil

        StatCard {
            Text("Volumen")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(Fmt.compact(last.volume)) kg")
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let previous {
                let delta = last.volume - previous.volume
                HStack(spacing: 3) {
                    Image(systemName: delta > 0.5 ? "arrow.up.right" : (delta < -0.5 ? "arrow.down.right" : "arrow.right"))
                    Text("\(Fmt.signed(delta, compact: true)) ggü. davor")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(delta > 0.5 ? Theme.accent : (delta < -0.5 ? Theme.holiday : Color.secondary))
            } else {
                Text("erste Einheit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SessionsTile: View {
    let days: [ExerciseDayStat]
    let range: StatRange

    var body: some View {
        StatCard {
            Text("Einheiten")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(days.count)")
                .font(.title3.weight(.semibold))
            Text(range == .all ? "insgesamt" : "in \(range.spokenLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Gewicht: schwerster Satz + alle Sätze

private struct WeightCard: View {
    let days: [ExerciseDayStat]
    let range: StatRange

    @State private var selectedDate: Date?

    private struct SetDot: Identifiable {
        let id: String
        let date: Date
        let weight: Double
    }

    var body: some View {
        let dots: [SetDot] = days.flatMap { day in
            day.sets.enumerated().compactMap { item in
                item.element.weight.map { SetDot(id: "\(day.day)-\(item.offset)", date: day.date, weight: $0) }
            }
        }
        let tops = days.filter { $0.topWeight != nil }
        let domain = ChartScale.padded(dots.map { $0.weight })
        let xDomain = ChartScale.dates(days, range: range)
        let selected = ChartScale.nearest(tops, to: selectedDate)

        StatCard {
            CardHeader(title: "Gewicht", subtitle: "Schwerster Satz je Einheit, dahinter alle Sätze")

            Chart {
                ForEach(dots) { dot in
                    PointMark(x: .value("Datum", dot.date), y: .value("kg", dot.weight))
                        .symbolSize(28)
                        .foregroundStyle(Theme.context)
                }

                ForEach(tops) { day in
                    LineMark(x: .value("Datum", day.date), y: .value("kg", day.topWeight ?? 0))
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }

                if let last = tops.last, let weight = last.topWeight, selected == nil {
                    PointMark(x: .value("Datum", last.date), y: .value("kg", weight))
                        .symbolSize(130)
                        .foregroundStyle(Theme.card)
                    PointMark(x: .value("Datum", last.date), y: .value("kg", weight))
                        .symbolSize(50)
                        .foregroundStyle(Theme.accent)
                        .annotation(position: .top, alignment: .trailing, spacing: 6) {
                            Text("\(Fmt.weight(weight)) kg")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                }

                if let selected, let weight = selected.topWeight {
                    RuleMark(x: .value("Datum", selected.date))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .annotation(position: .top, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            ChartTooltip(title: Day.mediumDate(selected.day),
                                         lines: ["Schwerster Satz \(Fmt.weight(weight)) kg",
                                                 selected.sets.map { set in set.weight.map { w in Fmt.weight(w) } ?? "–" }.joined(separator: " · ") + " kg"])
                        }
                }
            }
            .chartYScale(domain: domain)
            .chartXScale(domain: xDomain)
            .chartXSelection(value: $selectedDate)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel {
                        if let number = value.as(Double.self) { Text(Fmt.weight(number)) }
                    }
                }
            }
            .frame(height: 190)
            .padding(.top, 8)

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Capsule().fill(Theme.accent).frame(width: 16, height: 2)
                    Text("Schwerster Satz")
                }
                HStack(spacing: 6) {
                    Circle().fill(Theme.context).frame(width: 7, height: 7)
                    Text("Alle Sätze")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Gestapelte Balken je Einheit (Wiederholungen / Volumen)

private enum StackMetric {
    case reps, volume

    func value(_ set: SetValue) -> Double {
        switch self {
        case .reps:
            return Double(set.reps ?? 0)
        case .volume:
            guard let w = set.weight, let r = set.reps else { return 0 }
            return w * Double(r)
        }
    }

    func total(_ day: ExerciseDayStat) -> Double {
        self == .reps ? Double(day.totalReps) : day.volume
    }

    func format(_ value: Double) -> String {
        self == .reps ? String(Int(value.rounded())) : Fmt.compact(value)
    }

    var unit: String { self == .reps ? "Wdh." : "kg" }
}

private struct SetStackCard: View {
    let title: String
    let subtitle: String
    let metric: StackMetric
    let days: [ExerciseDayStat]

    @State private var selectedDay: String?

    private struct Segment: Identifiable {
        let id: String
        let day: DayKey
        let group: String
        let start: Double
        let end: Double
        let isTop: Bool
    }

    /// Höchstens die letzten 40 Einheiten, damit die Balken lesbar bleiben.
    private var visibleDays: [ExerciseDayStat] {
        Array(days.filter { metric.total($0) > 0 }.suffix(40))
    }

    var body: some View {
        let visible = visibleDays
        let maxTotal = visible.map { metric.total($0) }.max() ?? 1
        let domainTop = maxTotal * 1.18
        let gap = domainTop * 0.012   // ≈ 2 pt Abstand zwischen den Segmenten
        let segments = makeSegments(visible, gap: gap)
        let groups = ExerciseStats.setGroupLabels.filter { label in segments.contains { $0.group == label } }
        let colors = groups.compactMap { label in
            ExerciseStats.setGroupLabels.firstIndex(of: label).map { Theme.setRamp[$0] }
        }
        let barRatio = min(0.65, 24.0 * Double(max(visible.count, 1)) / 300.0)
        let ticks = tickDays(visible.map { $0.day })
        let selected = visible.first { $0.day == selectedDay }
        let lastDay = visible.last?.day

        StatCard {
            CardHeader(title: title, subtitle: subtitle)

            Chart {
                ForEach(segments) { segment in
                    BarMark(x: .value("Einheit", segment.day),
                            yStart: .value(metric.unit, segment.start),
                            yEnd: .value(metric.unit, segment.end),
                            width: .ratio(barRatio))
                        .foregroundStyle(by: .value("Satz", segment.group))
                        .cornerRadius(segment.isTop ? 4 : 1.5)
                        .opacity(selectedDay == nil || selectedDay == segment.day ? 1 : 0.35)
                }

                // Wert nur am letzten Balken (bzw. am ausgewählten)
                if let lastDay, let last = visible.last, selected == nil {
                    RuleMark(x: .value("Einheit", lastDay))
                        .foregroundStyle(Color.clear)
                        .annotation(position: .top, alignment: .center, spacing: 0,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            Text(metric.format(metric.total(last)))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                }

                if let selected {
                    RuleMark(x: .value("Einheit", selected.day))
                        .foregroundStyle(Color.clear)
                        .annotation(position: .top, spacing: 0,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            ChartTooltip(title: Day.mediumDate(selected.day),
                                         lines: ["\(metric.format(metric.total(selected))) \(metric.unit) gesamt",
                                                 selected.sets.map { metric.format(metric.value($0)) }.joined(separator: " · ")])
                        }
                }
            }
            .chartForegroundStyleScale(domain: groups, range: colors)
            .chartYScale(domain: 0...domainTop)
            .chartXSelection(value: $selectedDay)
            .chartXAxis {
                AxisMarks(values: ticks) { value in
                    AxisValueLabel {
                        if let key = value.as(String.self) { Text(Day.tinyDate(key)) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel {
                        if let number = value.as(Double.self) { Text(metric.format(number)) }
                    }
                }
            }
            .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
            .frame(height: 220)
            .padding(.top, 8)
        }
    }

    private func makeSegments(_ days: [ExerciseDayStat], gap: Double) -> [Segment] {
        var result: [Segment] = []
        for day in days {
            // Werte je Satzgruppe summieren (ab Satz 5 zusammengefasst)
            var grouped: [(label: String, value: Double)] = []
            for (index, set) in day.sets.enumerated() {
                let value = metric.value(set)
                guard value > 0 else { continue }
                let label = ExerciseStats.setGroupLabel(index)
                if let last = grouped.last, last.label == label {
                    grouped[grouped.count - 1].value += value
                } else {
                    grouped.append((label, value))
                }
            }
            var cumulative = 0.0
            for (index, item) in grouped.enumerated() {
                let isTop = index == grouped.count - 1
                let end = cumulative + item.value
                let visibleEnd = isTop ? end : max(cumulative + item.value * 0.5, end - gap)
                result.append(Segment(id: "\(day.day)-\(index)",
                                      day: day.day,
                                      group: item.label,
                                      start: cumulative,
                                      end: visibleEnd,
                                      isTop: isTop))
                cumulative = end
            }
        }
        return result
    }

    /// Höchstens 4 gleichmäßig verteilte Datumsbeschriftungen.
    private func tickDays(_ keys: [DayKey]) -> [DayKey] {
        guard keys.count > 4 else { return keys }
        let step = Double(keys.count - 1) / 3.0
        return (0...3).map { keys[Int((Double($0) * step).rounded())] }
    }
}

// MARK: - Rekorde

private struct RecordsCard: View {
    let records: [PersonalRecord]

    var body: some View {
        if !records.isEmpty {
            StatCard {
                CardHeader(title: "Rekorde")
                VStack(spacing: 0) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.title)
                                    .font(.subheadline)
                                Text(Day.mediumDate(record.day))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(record.value)
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                if let detail = record.detail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        if index < records.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Verlauf

private struct HistoryCard: View {
    let days: [ExerciseDayStat]
    @State private var showAll = false

    var body: some View {
        let ordered = Array(days.reversed())
        let shown = showAll ? ordered : Array(ordered.prefix(8))

        StatCard {
            CardHeader(title: "Alle Einheiten", subtitle: "\(days.count) insgesamt")

            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, day in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(Day.mediumDate(day.day))
                                .font(.subheadline.weight(.medium))
                            if day.isRecord {
                                Label("Rekord", systemImage: "star.fill")
                                    .font(.caption2.weight(.semibold))
                                    .labelStyle(.titleAndIcon)
                                    .foregroundStyle(Theme.accent)
                            }
                            Spacer()
                            if let oneRepMax = day.oneRepMax {
                                Text("1RM ≈ \(Fmt.weight(oneRepMax.rounded(toStep: 0.5))) kg")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        Text(day.sets.map { setShort($0) }.joined(separator: "  ·  "))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)

                    if index < shown.count - 1 {
                        Divider()
                    }
                }
            }

            if days.count > 8 {
                Button(showAll ? "Weniger anzeigen" : "Alle \(days.count) anzeigen") {
                    withAnimation { showAll.toggle() }
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
            }
        }
    }

    private func setShort(_ set: SetValue) -> String {
        let reps = set.reps.map { String($0) } ?? "–"
        guard let weight = set.weight else { return "\(reps) Wdh." }
        return "\(Fmt.weight(weight)) × \(reps)"
    }
}
