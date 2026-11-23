import SwiftUI
import SwiftData

/// Every past session for one exercise, with each set's weight and reps.
struct ExerciseHistoryView: View {
    let exercise: Exercise
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    @AppStorage(SettingsKey.weightUnit) private var unit: WeightUnit = .lb

    private var history: [(date: Date, sets: [SetEntry])] {
        sessions.compactMap { s in
            let sets = s.entries.filter { $0.exercise == exercise }.flatMap(\.orderedSets)
            return sets.isEmpty ? nil : (s.start, sets)
        }
    }

    var body: some View {
        List {
            let working = history.flatMap(\.sets).filter { !$0.isWarmup && $0.reps > 0 }
            if let best = working.max(by: { $0.weightKg < $1.weightKg }),
               let top1RM = working.map(\.estimated1RM).max() {
                Section("Bests") {
                    LabeledContent("Heaviest set", value: "\(unit.format(best.weightKg)) × \(best.reps)")
                    LabeledContent("Estimated 1-rep max", value: unit.format(top1RM))
                    LabeledContent("Times performed", value: "\(history.count)")
                }
            }
            ForEach(history, id: \.date) { item in
                Section(item.date.formatted(.dateTime.weekday().month().day().year())) {
                    ForEach(Array(item.sets.enumerated()), id: \.offset) { i, set in
                        HStack {
                            Text("Set \(i + 1)").foregroundStyle(.secondary)
                            if set.isWarmup { Text("warm-up").font(.caption).foregroundStyle(.orange) }
                            Spacer()
                            Text("\(unit.format(set.weightKg)) × \(set.reps)").monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
        .overlay {
            if history.isEmpty {
                ContentUnavailableView("No history yet", systemImage: "clock",
                                       description: Text("Sets you log for \(exercise.name) will show up here."))
            }
        }
    }
}

/// All exercises you've logged, each linking to its history.
struct ExerciseListView: View {
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var entries: [ExerciseEntry]

    var body: some View {
        let used = Set(entries.compactMap { $0.exercise?.persistentModelID })
        List {
            Section("Logged") {
                ForEach(exercises.filter { used.contains($0.persistentModelID) }) { ex in
                    NavigationLink(ex.name) { ExerciseHistoryView(exercise: ex) }
                }
            }
            Section("Not tried yet") {
                ForEach(exercises.filter { !used.contains($0.persistentModelID) }) { ex in
                    NavigationLink(ex.name) { ExerciseHistoryView(exercise: ex) }
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Exercises")
    }
}
