import SwiftUI
import SwiftData

struct WorkoutListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    @AppStorage(SettingsKey.weightUnit) private var unit: WeightUnit = .lb
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button {
                        let session = WorkoutSession()
                        context.insert(session)
                        path.append(session)
                    } label: {
                        Label("Start workout", systemImage: "plus.circle.fill").font(.headline)
                    }
                    NavigationLink { ExerciseListView() } label: {
                        Label("Exercise history", systemImage: "clock.arrow.circlepath")
                    }
                }
                Section("History") {
                    if sessions.isEmpty {
                        Text("No workouts yet. Tap Start workout to log your first one.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(sessions) { session in
                        NavigationLink(value: session) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.title).font(.headline).lineLimit(1)
                                HStack {
                                    Text(session.start, format: .dateTime.weekday().month().day())
                                    Text("·")
                                    Text("\(session.totalSets) sets")
                                    Text("·")
                                    Text(unit.format(session.totalVolumeKg))
                                }
                                .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { sessions[$0] }.forEach(context.delete)
                    }
                }
            }
            .navigationTitle("Workouts")
            .navigationDestination(for: WorkoutSession.self) { ActiveWorkoutView(session: $0) }
        }
    }
}

struct ActiveWorkoutView: View {
    @Bindable var session: WorkoutSession
    @Environment(\.modelContext) private var context
    @Environment(HealthKitManager.self) private var health
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.weightUnit) private var unit: WeightUnit = .lb
    @AppStorage(SettingsKey.saveToHealth) private var saveToHealth = true
    @Query(sort: \WorkoutSession.start, order: .reverse) private var allSessions: [WorkoutSession]
    @State private var showingPicker = false

    var body: some View {
        List {
            ForEach(session.orderedEntries) { entry in
                Section {
                    HStack {
                        Text("Set").frame(width: 34, alignment: .leading)
                        Text(unit.rawValue).frame(maxWidth: .infinity)
                        Text("Reps").frame(maxWidth: .infinity)
                        Text("Warm-up").frame(width: 64)
                    }
                    .font(.caption).foregroundStyle(.secondary)

                    ForEach(entry.orderedSets) { set in
                        SetRow(set: set, index: set.order + 1, unit: unit)
                    }
                    .onDelete { offsets in
                        let ordered = entry.orderedSets
                        offsets.map { ordered[$0] }.forEach(context.delete)
                        renumber(entry)
                    }

                    Button {
                        addSet(to: entry)
                    } label: {
                        Label("Add set", systemImage: "plus")
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        if let ex = entry.exercise {
                            NavigationLink { ExerciseHistoryView(exercise: ex) } label: {
                                HStack(spacing: 4) {
                                    Text(ex.name).font(.headline)
                                    Image(systemName: "clock.arrow.circlepath").font(.caption)
                                }
                            }
                            .textCase(nil)
                        }
                        if let last = previousEntry(for: entry) {
                            Text("Last time: " + last.orderedSets.filter { !$0.isWarmup }
                                .map { "\($0.reps)×\(unit.format($0.weightKg))" }
                                .joined(separator: ", "))
                                .font(.caption).textCase(nil).lineLimit(1)
                        }
                    }
                }
            }
            .onDelete { offsets in
                let ordered = session.orderedEntries
                offsets.map { ordered[$0] }.forEach(context.delete)
            }

            Section {
                Button {
                    showingPicker = true
                } label: {
                    Label("Add exercise", systemImage: "dumbbell")
                }
                TextField("Notes", text: $session.notes, axis: .vertical)
            }

            if session.end == nil {
                Section {
                    Button("Finish workout") { finish() }
                        .frame(maxWidth: .infinity).fontWeight(.semibold)
                        .disabled(session.entries.isEmpty)
                }
            } else {
                Section("Summary") {
                    LabeledContent("Duration", value: Duration.seconds(
                        (session.end ?? .now).timeIntervalSince(session.start))
                        .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                    LabeledContent("Sets", value: "\(session.totalSets)")
                    LabeledContent("Volume", value: unit.format(session.totalVolumeKg))
                }
            }
        }
        .navigationTitle(session.start.formatted(.dateTime.weekday(.wide).month().day()))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView { exercise in
                let entry = ExerciseEntry(exercise: exercise, order: session.entries.count)
                entry.session = session
                context.insert(entry)
                // Pre-fill the first set from last time to save typing.
                let template = previousEntry(for: entry)?.orderedSets.last { !$0.isWarmup }
                let set = SetEntry(order: 0, reps: template?.reps ?? 8, weightKg: template?.weightKg ?? 0)
                set.entry = entry
                context.insert(set)
            }
        }
    }

    private func previousEntry(for entry: ExerciseEntry) -> ExerciseEntry? {
        guard let exercise = entry.exercise else { return nil }
        return allSessions
            .filter { $0.start < session.start }
            .lazy
            .compactMap { $0.entries.first { $0.exercise == exercise } }
            .first
    }

    private func addSet(to entry: ExerciseEntry) {
        let last = entry.orderedSets.last
        let set = SetEntry(order: entry.sets.count, reps: last?.reps ?? 8, weightKg: last?.weightKg ?? 0)
        set.entry = entry
        context.insert(set)
    }

    private func renumber(_ entry: ExerciseEntry) {
        for (i, s) in entry.orderedSets.enumerated() { s.order = i }
    }

    private func finish() {
        session.end = .now
        try? context.save()
        if saveToHealth {
            let (start, end, volume) = (session.start, session.end!, session.totalVolumeKg)
            Task { await health.saveStrengthWorkout(start: start, end: end, totalVolumeKg: volume) }
        }
        dismiss()
    }
}

private struct SetRow: View {
    @Bindable var set: SetEntry
    let index: Int
    let unit: WeightUnit

    var body: some View {
        HStack {
            Text("\(index)").frame(width: 34, alignment: .leading).foregroundStyle(.secondary)
            TextField(unit.rawValue, value: Binding(
                get: { (unit.display(set.weightKg) * 10).rounded() / 10 },
                set: { set.weightKg = unit.toKg($0) }), format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            TextField("Reps", value: $set.reps, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Toggle("", isOn: $set.isWarmup).labelsHidden().frame(width: 64)
        }
        .textFieldStyle(.roundedBorder)
    }
}

struct ExercisePickerView: View {
    var onPick: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var search = ""
    @State private var showingNew = false

    private var filtered: [Exercise] {
        search.isEmpty ? exercises : exercises.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(MuscleGroup.allCases) { group in
                    let items = filtered.filter { $0.primary.first == group }
                    if !items.isEmpty {
                        Section(group.name) {
                            ForEach(items) { exercise in
                                Button(exercise.name) { onPick(exercise); dismiss() }
                                    .foregroundStyle(.primary)
                            }
                            .onDelete { offsets in
                                offsets.map { items[$0] }.filter(\.isCustom).forEach(context.delete)
                            }
                        }
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("New", systemImage: "plus") { showingNew = true }
                }
            }
            .sheet(isPresented: $showingNew) { NewExerciseView(initialName: search) }
        }
    }
}

private struct NewExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State var name: String
    @State private var primary: Set<MuscleGroup> = []
    @State private var secondary: Set<MuscleGroup> = []

    init(initialName: String) { _name = State(initialValue: initialName) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Exercise name", text: $name)
                Section("Main muscles") { muscleToggles($primary) }
                Section("Also works") { muscleToggles($secondary) }
            }
            .navigationTitle("New exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        context.insert(Exercise(name: name.trimmingCharacters(in: .whitespaces),
                                                primary: MuscleGroup.allCases.filter(primary.contains),
                                                secondary: MuscleGroup.allCases.filter(secondary.contains),
                                                isCustom: true))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || primary.isEmpty)
                }
            }
        }
    }

    private func muscleToggles(_ selection: Binding<Set<MuscleGroup>>) -> some View {
        ForEach(MuscleGroup.allCases) { group in
            Toggle(group.name, isOn: Binding(
                get: { selection.wrappedValue.contains(group) },
                set: { if $0 { selection.wrappedValue.insert(group) } else { selection.wrappedValue.remove(group) } }))
        }
    }
}
