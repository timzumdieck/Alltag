import SwiftUI
import SwiftData
import Charts

struct ExerciseLog: Identifiable {
    let id: UUID
    let day: DayKey
    let sets: [SetValue]
}

enum StatMetric {
    case weight, reps, volume

    func value(_ set: SetValue) -> Double? {
        switch self {
        case .weight:
            return set.weight
        case .reps:
            guard let reps = set.reps else { return nil }
            return Double(reps)
        case .volume:
            guard let weight = set.weight, let reps = set.reps else { return nil }
            return weight * Double(reps)
        }
    }

    /// „Gesamt pro Tag“: Gewicht = höchstes Gewicht, Wiederholungen/Volumen = Summe.
    func combine(_ values: [Double]) -> Double {
        switch self {
        case .weight: return values.max() ?? 0
        case .reps, .volume: return values.reduce(0, +)
        }
    }
}

enum ChartMode: String, CaseIterable, Identifiable {
    case perSet = "Pro Satz"
    case total = "Gesamt pro Tag"
    var id: String { rawValue }
}

struct ChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let series: String
}

struct ExerciseStatsView: View {
    let exerciseID: UUID

    @Environment(\.modelContext) private var ctx
    @Query private var sessions: [WorkoutSession]
    @Query private var exercises: [Exercise]

    @State private var showRename = false
    @State private var renameText = ""

    private var exercise: Exercise? {
        exercises.first { $0.id == exerciseID }
    }

    private var logs: [ExerciseLog] {
        var result: [ExerciseLog] = []
        for session in sessions where session.isCompleted {
            let sets = session.exercises
                .filter { $0.exerciseID == exerciseID }
                .flatMap { $0.sets }
            if sets.contains(where: { !$0.isEmpty }) {
                result.append(ExerciseLog(id: session.id, day: session.day, sets: sets))
            }
        }
        return result.sorted { $0.day < $1.day }
    }

    var body: some View {
        let logs = self.logs

        ScrollView {
            VStack(spacing: 20) {
                if logs.isEmpty {
                    EmptyStateView(symbol: "chart.xyaxis.line",
                                   title: "Noch keine Daten",
                                   message: "Schließe ein Training mit dieser Übung ab, um hier deinen Verlauf zu sehen.")
                } else {
                    StatChartCard(title: "Gewicht", unit: "kg", metric: .weight, logs: logs)
                    StatChartCard(title: "Wiederholungen", unit: "Wdh.", metric: .reps, logs: logs)
                    StatChartCard(title: "Volumen", unit: "kg × Wdh.", metric: .volume, logs: logs)
                    historyCard(logs)
                }
            }
            .padding(20)
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

    private func historyCard(_ logs: [ExerciseLog]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Alle Einheiten")
                .font(.headline)
                .padding(.bottom, 8)

            ForEach(Array(logs.reversed())) { log in
                VStack(alignment: .leading, spacing: 6) {
                    Text(Day.mediumDate(log.day))
                        .font(.subheadline.weight(.medium))
                    ForEach(Array(log.sets.enumerated()), id: \.offset) { item in
                        HStack(spacing: 8) {
                            Text("Satz \(item.offset + 1)")
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .leading)
                            Text(Fmt.setText(item.element))
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)

                if log.id != logs.first?.id {
                    Divider()
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
    }
}

// MARK: - Diagrammkarte

struct StatChartCard: View {
    let title: String
    let unit: String
    let metric: StatMetric
    let logs: [ExerciseLog]

    @State private var mode: ChartMode = .perSet

    private var perSetPoints: [ChartPoint] {
        var points: [ChartPoint] = []
        for log in logs {
            for (index, set) in log.sets.enumerated() {
                if let value = metric.value(set) {
                    points.append(ChartPoint(date: Day.noon(log.day), value: value, series: "Satz \(index + 1)"))
                }
            }
        }
        return points
    }

    private var totalPoints: [ChartPoint] {
        var byDay: [DayKey: [Double]] = [:]
        for log in logs {
            byDay[log.day, default: []].append(contentsOf: log.sets.compactMap { metric.value($0) })
        }
        return byDay
            .filter { !$0.value.isEmpty }
            .sorted { $0.key < $1.key }
            .map { ChartPoint(date: Day.noon($0.key), value: metric.combine($0.value), series: "Gesamt") }
    }

    private var seriesDomain: [String] {
        let maxSets = logs.map { $0.sets.count }.max() ?? 1
        return (0..<max(1, maxSets)).map { "Satz \($0 + 1)" }
    }

    private var seriesColors: [Color] {
        seriesDomain.indices.map { Theme.chartPalette[$0 % Theme.chartPalette.count] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Ansicht", selection: $mode) {
                ForEach(ChartMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if mode == .perSet {
                perSetChart
            } else {
                totalChart
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
    }

    private var perSetChart: some View {
        let points = perSetPoints
        return Chart(points) { point in
            LineMark(x: .value("Datum", point.date),
                     y: .value(title, point.value),
                     series: .value("Satz", point.series))
                .foregroundStyle(by: .value("Satz", point.series))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.5))

            PointMark(x: .value("Datum", point.date),
                      y: .value(title, point.value))
                .foregroundStyle(by: .value("Satz", point.series))
                .symbolSize(22)
        }
        .chartForegroundStyleScale(domain: seriesDomain, range: seriesColors)
        .chartLegend(position: .bottom, alignment: .leading)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .frame(height: 200)
    }

    private var totalChart: some View {
        let points = totalPoints
        return Chart(points) { point in
            LineMark(x: .value("Datum", point.date),
                     y: .value(title, point.value))
                .foregroundStyle(Theme.accent)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.5))

            PointMark(x: .value("Datum", point.date),
                      y: .value(title, point.value))
                .foregroundStyle(Theme.accent)
                .symbolSize(22)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .frame(height: 200)
    }
}
