import Foundation

/// Kennzahlen einer Übung pro Trainingstag – Grundlage für Diagramme, Rekorde und Verlauf.
struct ExerciseDayStat: Identifiable {
    let day: DayKey
    let date: Date
    /// Alle Sätze des Tages in Reihenfolge (mehrere Einheiten am selben Tag werden zusammengefasst)
    let sets: [SetValue]
    /// Satz mit dem höchsten geschätzten 1RM
    let bestSet: SetValue?
    /// Geschätztes Ein-Wiederholungs-Maximum (Epley) des besten Satzes
    let oneRepMax: Double?
    /// Schwerster Satz des Tages
    let topWeight: Double?
    /// Meiste Wiederholungen in einem Satz
    let maxReps: Int?
    let totalReps: Int
    /// Summe aus Gewicht × Wiederholungen
    let volume: Double
    /// Neuer Bestwert beim geschätzten 1RM (bzw. bei Wiederholungen ohne Gewicht)
    var isRecord: Bool = false

    var id: DayKey { day }
}

enum StatRange: String, CaseIterable, Identifiable {
    case threeMonths = "3 M"
    case sixMonths = "6 M"
    case year = "1 J"
    case all = "Alle"

    var id: String { rawValue }

    var startDay: DayKey? {
        let months: Int
        switch self {
        case .threeMonths: months = 3
        case .sixMonths: months = 6
        case .year: months = 12
        case .all: return nil
        }
        let base = Day.noon(Day.today)
        let date = Day.calendar.date(byAdding: .month, value: -months, to: base) ?? base
        return Day.key(for: date)
    }

    var spokenLabel: String {
        switch self {
        case .threeMonths: return "3 Monaten"
        case .sixMonths: return "6 Monaten"
        case .year: return "einem Jahr"
        case .all: return "Beginn"
        }
    }
}

struct PersonalRecord: Identifiable {
    let id: String
    let title: String
    let value: String
    let detail: String?
    let day: DayKey
}

enum ExerciseStats {
    /// Geschätztes 1RM nach Epley: Gewicht × (1 + Wdh. / 30). Bei 1 Wiederholung = Gewicht.
    static func oneRepMax(_ set: SetValue) -> Double? {
        guard let weight = set.weight, weight > 0, let reps = set.reps, reps > 0 else { return nil }
        if reps == 1 { return weight }
        return weight * (1 + Double(reps) / 30)
    }

    /// Alle abgeschlossenen Einheiten einer Übung, pro Tag zusammengefasst, chronologisch.
    static func days(for exerciseID: UUID, sessions: [WorkoutSession]) -> [ExerciseDayStat] {
        var setsByDay: [DayKey: [SetValue]] = [:]
        let completed = sessions
            .filter { $0.isCompleted }
            .sorted { ($0.day, $0.completedAt ?? .distantPast) < ($1.day, $1.completedAt ?? .distantPast) }
        for session in completed {
            let sets = session.exercises
                .filter { $0.exerciseID == exerciseID }
                .flatMap { $0.sets }
                .filter { !$0.isEmpty }
            if !sets.isEmpty {
                setsByDay[session.day, default: []].append(contentsOf: sets)
            }
        }

        var result: [ExerciseDayStat] = []
        for day in setsByDay.keys.sorted() {
            let sets = setsByDay[day] ?? []
            var best: SetValue?
            var bestValue: Double?
            for set in sets {
                if let value = oneRepMax(set), value > (bestValue ?? -1) {
                    best = set
                    bestValue = value
                }
            }
            let weights = sets.compactMap { $0.weight }
            let reps = sets.compactMap { $0.reps }
            let volume = sets.reduce(0.0) { sum, set in
                guard let w = set.weight, let r = set.reps else { return sum }
                return sum + w * Double(r)
            }
            result.append(ExerciseDayStat(day: day,
                                          date: Day.noon(day),
                                          sets: sets,
                                          bestSet: best,
                                          oneRepMax: bestValue,
                                          topWeight: weights.max(),
                                          maxReps: reps.max(),
                                          totalReps: reps.reduce(0, +),
                                          volume: volume))
        }

        // Rekorde markieren (über die gesamte Historie, nicht nur den sichtbaren Zeitraum)
        let usesWeight = result.contains { $0.oneRepMax != nil }
        var bestSoFar: Double = -1
        for index in result.indices {
            let value: Double? = usesWeight ? result[index].oneRepMax : result[index].maxReps.map { Double($0) }
            if let value, value > bestSoFar + 0.0001 {
                // Der allererste Wert ist noch kein „Rekord“
                result[index].isRecord = bestSoFar >= 0
                bestSoFar = value
            }
        }
        return result
    }

    static func filter(_ days: [ExerciseDayStat], range: StatRange) -> [ExerciseDayStat] {
        guard let start = range.startDay else { return days }
        return days.filter { $0.day >= start }
    }

    static func records(_ days: [ExerciseDayStat]) -> [PersonalRecord] {
        var records: [PersonalRecord] = []

        if let best = days.filter({ $0.oneRepMax != nil }).max(by: { $0.oneRepMax! < $1.oneRepMax! }),
           let value = best.oneRepMax {
            records.append(PersonalRecord(id: "1rm",
                                          title: "Geschätztes 1RM",
                                          value: "\(Fmt.weight(value.rounded(toStep: 0.5))) kg",
                                          detail: best.bestSet.map { Fmt.setText($0) },
                                          day: best.day))
        }

        // Schwerster Satz (bei gleichem Gewicht: mehr Wiederholungen)
        var heaviest: (SetValue, DayKey)?
        var mostReps: (SetValue, DayKey)?
        for day in days {
            for set in day.sets {
                if let w = set.weight {
                    if let current = heaviest, let cw = current.0.weight {
                        if w > cw || (w == cw && (set.reps ?? 0) > (current.0.reps ?? 0)) { heaviest = (set, day.day) }
                    } else {
                        heaviest = (set, day.day)
                    }
                }
                if let r = set.reps, r > (mostReps?.0.reps ?? 0) {
                    mostReps = (set, day.day)
                }
            }
        }
        if let heaviest, let weight = heaviest.0.weight {
            records.append(PersonalRecord(id: "weight",
                                          title: "Schwerster Satz",
                                          value: "\(Fmt.weight(weight)) kg",
                                          detail: heaviest.0.reps.map { "× \($0) Wdh." },
                                          day: heaviest.1))
        }
        if let mostReps, let reps = mostReps.0.reps {
            records.append(PersonalRecord(id: "reps",
                                          title: "Meiste Wiederholungen",
                                          value: "\(reps) Wdh.",
                                          detail: mostReps.0.weight.map { "mit \(Fmt.weight($0)) kg" },
                                          day: mostReps.1))
        }
        if let best = days.filter({ $0.volume > 0 }).max(by: { $0.volume < $1.volume }) {
            records.append(PersonalRecord(id: "volume",
                                          title: "Höchstes Volumen",
                                          value: "\(Fmt.compact(best.volume)) kg",
                                          detail: "an einem Tag",
                                          day: best.day))
        }
        return records
    }

    /// Satznummer → Gruppe für die gestapelten Balken (ab Satz 5 zusammengefasst).
    static let maxSetGroups = 5

    static func setGroupLabel(_ index: Int) -> String {
        index >= maxSetGroups - 1 ? "Satz \(maxSetGroups)+" : "Satz \(index + 1)"
    }

    static var setGroupLabels: [String] {
        (0..<maxSetGroups).map { setGroupLabel($0) }
    }
}

extension Double {
    func rounded(toStep step: Double) -> Double {
        (self / step).rounded() * step
    }
}
