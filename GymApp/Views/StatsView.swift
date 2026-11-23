import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Environment(HealthKitManager.self) private var health
    @Query(sort: \WorkoutSession.start) private var sessions: [WorkoutSession]
    @Query(sort: \BodyMeasurement.date) private var measurements: [BodyMeasurement]
    @Query private var exercises: [Exercise]
    @AppStorage(SettingsKey.weightUnit) private var unit: WeightUnit = .lb
    @State private var selectedName: String?

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    private var exerciseNames: [String] {
        Array(Set(sessions.flatMap { $0.entries.compactMap { $0.exercise?.name } })).sorted()
    }

    private func history(for name: String) -> (e1rm: [Point], top: [Point]) {
        var e1rm: [Point] = [], top: [Point] = []
        for s in sessions {
            let entries = s.entries.filter { $0.exercise?.name == name }
            let working = entries.flatMap(\.sets).filter { !$0.isWarmup && $0.reps > 0 }
            guard !working.isEmpty else { continue }
            e1rm.append(Point(date: s.start, value: unit.display(working.map(\.estimated1RM).max()!)))
            top.append(Point(date: s.start, value: unit.display(working.map(\.weightKg).max()!)))
        }
        return (e1rm, top)
    }

    private var weeklyVolume: [Point] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: sessions) { cal.dateInterval(of: .weekOfYear, for: $0.start)!.start }
        let cutoff = cal.date(byAdding: .weekOfYear, value: -12, to: .now)!
        return grouped.filter { $0.key >= cutoff }
            .map { Point(date: $0.key, value: unit.display($0.value.reduce(0) { $0 + $1.totalVolumeKg })) }
            .sorted { $0.date < $1.date }
    }

    private var bodyweight: [Point] {
        // Health data includes weigh-ins from smart scales and MyFitnessPal; fall back to app entries.
        let fromHealth = health.weightHistory.map { Point(date: $0.date, value: unit.display($0.kg)) }
        if !fromHealth.isEmpty { return fromHealth }
        return measurements.compactMap { m in m.weightKg.map { Point(date: m.date, value: unit.display($0)) } }
    }

    private var personalRecords: [(name: String, kg: Double, reps: Int, date: Date)] {
        exerciseNames.compactMap { name in
            let sets = sessions.flatMap { s in
                s.entries.filter { $0.exercise?.name == name }.flatMap(\.sets).map { (s.start, $0) }
            }.filter { !$0.1.isWarmup && $0.1.reps > 0 }
            guard let best = sets.max(by: { $0.1.weightKg < $1.1.weightKg }) else { return nil }
            return (name, best.1.weightKg, best.1.reps, best.0)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if exerciseNames.isEmpty {
                    ContentUnavailableView("No data yet", systemImage: "chart.line.uptrend.xyaxis",
                                           description: Text("Log a few workouts and your progress charts will show up here."))
                } else {
                    Section("Strength") {
                        Picker("Exercise", selection: Binding(
                            get: { selectedName ?? exerciseNames.first! },
                            set: { selectedName = $0 })) {
                            ForEach(exerciseNames, id: \.self) { Text($0) }
                        }
                        let h = history(for: selectedName ?? exerciseNames.first!)
                        Chart {
                            ForEach(h.e1rm) {
                                LineMark(x: .value("Date", $0.date), y: .value(unit.rawValue, $0.value))
                                    .foregroundStyle(by: .value("Series", "Estimated 1RM"))
                                PointMark(x: .value("Date", $0.date), y: .value(unit.rawValue, $0.value))
                                    .foregroundStyle(by: .value("Series", "Estimated 1RM"))
                            }
                            ForEach(h.top) {
                                LineMark(x: .value("Date", $0.date), y: .value(unit.rawValue, $0.value))
                                    .foregroundStyle(by: .value("Series", "Heaviest set"))
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 220)
                    }

                    Section("Weekly volume (\(unit.rawValue))") {
                        Chart(weeklyVolume) {
                            BarMark(x: .value("Week", $0.date, unit: .weekOfYear), y: .value("Volume", $0.value))
                        }
                        .frame(height: 180)
                    }

                    Section("Personal records") {
                        ForEach(personalRecords, id: \.name) { pr in
                            NavigationLink {
                                if let ex = exercises.first(where: { $0.name == pr.name }) { ExerciseHistoryView(exercise: ex) }
                            } label: {
                                LabeledContent(pr.name) {
                                    VStack(alignment: .trailing) {
                                        Text("\(unit.format(pr.kg)) × \(pr.reps)").fontWeight(.semibold)
                                        Text(pr.date, format: .dateTime.month().day().year()).font(.caption)
                                    }
                                }
                            }
                        }
                    }
                }

                if !bodyweight.isEmpty {
                    Section("Body weight (\(unit.rawValue))") {
                        Chart(bodyweight) {
                            LineMark(x: .value("Date", $0.date), y: .value("Weight", $0.value))
                                .interpolationMethod(.monotone)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 180)
                    }
                }
            }
            .navigationTitle("Progress")
        }
    }
}
