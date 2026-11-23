import Foundation
import SwiftData

enum MuscleGroup: String, Codable, CaseIterable, Identifiable {
    case chest, shoulders, traps, biceps, triceps, forearms, abs, obliques
    case upperBack, lats, lowerBack, glutes, quads, hamstrings, calves

    var id: String { rawValue }
    var name: String {
        switch self {
        case .upperBack: "Upper back"
        case .lowerBack: "Lower back"
        default: rawValue.capitalized
        }
    }
}

@Model
final class Exercise {
    /// Stable ID shared with the cloud copy of this record.
    var uuid: UUID = UUID()
    var name: String
    var primaryRaw: [String]
    var secondaryRaw: [String]
    var isCustom: Bool

    init(name: String, primary: [MuscleGroup], secondary: [MuscleGroup] = [], isCustom: Bool = false) {
        self.name = name
        self.primaryRaw = primary.map(\.rawValue)
        self.secondaryRaw = secondary.map(\.rawValue)
        self.isCustom = isCustom
    }

    var primary: [MuscleGroup] { primaryRaw.compactMap(MuscleGroup.init) }
    var secondary: [MuscleGroup] { secondaryRaw.compactMap(MuscleGroup.init) }
}

@Model
final class WorkoutSession {
    /// Stable ID shared with the cloud copy of this record.
    var uuid: UUID = UUID()
    var start: Date
    var end: Date?
    var notes: String
    @Relationship(deleteRule: .cascade, inverse: \ExerciseEntry.session)
    var entries: [ExerciseEntry] = []

    init(start: Date = .now, notes: String = "") {
        self.start = start
        self.notes = notes
    }

    var orderedEntries: [ExerciseEntry] { entries.sorted { $0.order < $1.order } }
    var totalVolumeKg: Double { entries.reduce(0) { $0 + $1.volumeKg } }
    var totalSets: Int { entries.reduce(0) { $0 + $1.sets.count } }
    var title: String {
        let names = orderedEntries.prefix(3).compactMap { $0.exercise?.name }
        return names.isEmpty ? "Workout" : names.joined(separator: ", ")
    }
}

@Model
final class ExerciseEntry {
    /// Stable ID shared with the cloud copy of this record.
    var uuid: UUID = UUID()
    var order: Int
    var exercise: Exercise?
    var session: WorkoutSession?
    @Relationship(deleteRule: .cascade, inverse: \SetEntry.entry)
    var sets: [SetEntry] = []

    init(exercise: Exercise?, order: Int) {
        self.exercise = exercise
        self.order = order
    }

    var orderedSets: [SetEntry] { sets.sorted { $0.order < $1.order } }
    var volumeKg: Double { sets.reduce(0) { $0 + $1.weightKg * Double($1.reps) } }
    var bestEstimated1RM: Double { sets.map(\.estimated1RM).max() ?? 0 }
}

@Model
final class SetEntry {
    /// Stable ID shared with the cloud copy of this record.
    var uuid: UUID = UUID()
    var order: Int
    var reps: Int
    var weightKg: Double
    var isWarmup: Bool
    var entry: ExerciseEntry?

    init(order: Int, reps: Int, weightKg: Double, isWarmup: Bool = false) {
        self.order = order
        self.reps = reps
        self.weightKg = weightKg
        self.isWarmup = isWarmup
    }

    /// Epley formula estimate of a one-rep max.
    var estimated1RM: Double {
        guard reps > 0, !isWarmup else { return 0 }
        return reps == 1 ? weightKg : weightKg * (1 + Double(reps) / 30)
    }
}

@Model
final class BodyMeasurement {
    /// Stable ID shared with the cloud copy of this record.
    var uuid: UUID = UUID()
    var date: Date
    var weightKg: Double?
    var bodyFatPercent: Double?
    var chestCm: Double?
    var waistCm: Double?
    var hipsCm: Double?
    var armCm: Double?
    var thighCm: Double?
    var calfCm: Double?
    var shouldersCm: Double?

    init(date: Date = .now) { self.date = date }
}
