import SwiftUI
import SwiftData
import SceneKit

enum MuscleVolume {
    /// Working sets per muscle in the last `days` days. Main muscles count a full set,
    /// secondary muscles half a set.
    static func sets(in sessions: [WorkoutSession], days: Int) -> [MuscleGroup: Double] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        var result: [MuscleGroup: Double] = [:]
        for session in sessions where session.start >= cutoff {
            for entry in session.entries {
                guard let ex = entry.exercise else { continue }
                let working = Double(entry.sets.filter { !$0.isWarmup && $0.reps > 0 }.count)
                ex.primary.forEach { result[$0, default: 0] += working }
                ex.secondary.forEach { result[$0, default: 0] += working / 2 }
            }
        }
        return result
    }
}

struct BodyView: View {
    enum Mode: String, CaseIterable { case muscles = "Muscle map", shape = "Body shape" }

    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \BodyMeasurement.date) private var measurements: [BodyMeasurement]
    @AppStorage(SettingsKey.weightUnit) private var unit: WeightUnit = .lb

    @State private var mode: Mode = .muscles
    @State private var days = 7
    @State private var selectedIndex = 0.0
    @State private var compareWithFirst = true
    @State private var tapped: MuscleGroup?
    @State private var scene = SCNScene()
    @State private var showingAdd = false

    private var volume: [MuscleGroup: Double] { MuscleVolume.sets(in: sessions, days: days) }
    private var selectedMeasurement: BodyMeasurement? {
        measurements.isEmpty ? nil : measurements[min(Int(selectedIndex), measurements.count - 1)]
    }
    private var sceneKey: String {
        "\(mode)-\(days)-\(Int(selectedIndex))-\(compareWithFirst)-\(sessions.count)-\(measurements.count)-\(volume.values.reduce(0, +))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)

                    ZStack(alignment: .topLeading) {
                        BodySceneView(scene: scene) { tapped = $0 }
                            .frame(height: 420)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 20))
                        if mode == .muscles, let tapped {
                            Text("\(tapped.name): \(volume[tapped, default: 0], specifier: "%.1f") sets")
                                .font(.subheadline.weight(.semibold))
                                .padding(8).background(.thinMaterial, in: Capsule()).padding(10)
                        }
                    }
                    Text("Drag to rotate · pinch to zoom" + (mode == .muscles ? " · tap a muscle" : ""))
                        .font(.caption).foregroundStyle(.secondary)

                    if mode == .muscles { muscleControls } else { shapeControls }
                }
                .padding()
            }
            .navigationTitle("Body")
            .toolbar {
                NavigationLink { MeasurementHistoryView() } label: { Image(systemName: "list.bullet") }
                Button("Log", systemImage: "ruler") { showingAdd = true }
            }
            .sheet(isPresented: $showingAdd) { AddMeasurementView() }
            .onChange(of: sceneKey, initial: true) { rebuildScene() }
            .onChange(of: measurements.count) { selectedIndex = Double(max(measurements.count - 1, 0)) }
            .onAppear { selectedIndex = Double(max(measurements.count - 1, 0)) }
        }
    }

    private var muscleControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Period", selection: $days) {
                Text("7 days").tag(7); Text("14 days").tag(14); Text("30 days").tag(30)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 6) {
                Text("Untrained").font(.caption2)
                LinearGradient(colors: [Color(BodySceneBuilder.baseColor),
                                        Color(BodySceneBuilder.heatColor(sets: 1)),
                                        Color(BodySceneBuilder.heatColor(sets: 12))],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(height: 8).clipShape(Capsule())
                Text("12+ sets").font(.caption2)
            }

            let neglected = MuscleGroup.allCases.filter { volume[$0, default: 0] < 1 }
            if !neglected.isEmpty {
                Text("Not trained in the last \(days) days").font(.headline)
                Text(neglected.map(\.name).joined(separator: ", ")).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var shapeControls: some View {
        if measurements.isEmpty {
            ContentUnavailableView {
                Label("No measurements yet", systemImage: "ruler")
            } description: {
                Text("Log your weight and tape measurements and the model reshapes to match. Log again every few weeks to see your progress.")
            } actions: {
                Button("Log measurements") { showingAdd = true }.buttonStyle(.borderedProminent)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if let m = selectedMeasurement {
                    HStack {
                        Text(m.date, format: .dateTime.month().day().year()).font(.headline)
                        Spacer()
                        if let w = m.weightKg { Text(unit.format(w)).foregroundStyle(.secondary) }
                    }
                }
                if measurements.count > 1 {
                    Slider(value: $selectedIndex, in: 0...Double(measurements.count - 1), step: 1)
                    Toggle("Show first measurement as ghost", isOn: $compareWithFirst)
                }
            }
        }
    }

    private func rebuildScene() {
        var options = BodySceneBuilder.Options()
        var ghost: SCNNode?
        switch mode {
        case .muscles:
            let v = volume
            options.muscleColors = Dictionary(uniqueKeysWithValues: MuscleGroup.allCases.map {
                ($0, BodySceneBuilder.heatColor(sets: v[$0, default: 0]))
            })
        case .shape:
            options.shape = BodyShape(selectedMeasurement)
            if compareWithFirst, measurements.count > 1, Int(selectedIndex) > 0 {
                var g = BodySceneBuilder.Options()
                g.shape = BodyShape(measurements.first)
                g.opacity = 0.25
                ghost = BodySceneBuilder.makeBody(g)
            }
        }
        scene = BodySceneBuilder.makeScene(body: BodySceneBuilder.makeBody(options), ghost: ghost)
    }
}

struct AddMeasurementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(HealthKitManager.self) private var health
    @AppStorage(SettingsKey.weightUnit) private var wUnit: WeightUnit = .lb
    @AppStorage(SettingsKey.lengthUnit) private var lUnit: LengthUnit = .inch
    @AppStorage(SettingsKey.saveToHealth) private var saveToHealth = true

    @State private var date = Date.now
    @State private var weight: Double?
    @State private var bodyFat: Double?
    @State private var shoulders: Double?
    @State private var chest: Double?
    @State private var waist: Double?
    @State private var hips: Double?
    @State private var arm: Double?
    @State private var thigh: Double?
    @State private var calf: Double?

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Section("Weight") {
                    field("Body weight (\(wUnit.rawValue))", $weight)
                    field("Body fat (%)", $bodyFat)
                }
                Section {
                    field("Shoulders", $shoulders)
                    field("Chest", $chest)
                    field("Waist", $waist)
                    field("Hips", $hips)
                    field("Arm (flexed)", $arm)
                    field("Thigh", $thigh)
                    field("Calf", $calf)
                } header: {
                    Text("Measurements (\(lUnit.rawValue))")
                } footer: {
                    Text("Everything is optional. Measure around the widest point. The 3D model uses your body weight for anything you leave blank.")
                }
            }
            .navigationTitle("Log measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear {
                if weight == nil, let kg = health.summary.latestWeightKg { weight = (wUnit.display(kg) * 10).rounded() / 10 }
            }
        }
    }

    private func field(_ label: String, _ value: Binding<Double?>) -> some View {
        LabeledContent(label) {
            TextField("–", value: value, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        }
    }

    private func save() {
        let m = BodyMeasurement(date: date)
        m.weightKg = weight.map(wUnit.toKg)
        m.bodyFatPercent = bodyFat
        m.shouldersCm = shoulders.map(lUnit.toCm)
        m.chestCm = chest.map(lUnit.toCm)
        m.waistCm = waist.map(lUnit.toCm)
        m.hipsCm = hips.map(lUnit.toCm)
        m.armCm = arm.map(lUnit.toCm)
        m.thighCm = thigh.map(lUnit.toCm)
        m.calfCm = calf.map(lUnit.toCm)
        context.insert(m)
        if saveToHealth, let kg = m.weightKg {
            Task { await health.saveBodyMass(kg: kg, date: date) }
        }
        dismiss()
    }
}

struct MeasurementHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]
    @AppStorage(SettingsKey.weightUnit) private var wUnit: WeightUnit = .lb
    @AppStorage(SettingsKey.lengthUnit) private var lUnit: LengthUnit = .inch

    var body: some View {
        List {
            ForEach(measurements) { m in
                VStack(alignment: .leading, spacing: 4) {
                    Text(m.date, format: .dateTime.month().day().year()).font(.headline)
                    Text(summary(m)).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .onDelete { $0.map { measurements[$0] }.forEach(context.delete) }
        }
        .navigationTitle("Measurements")
        .overlay { if measurements.isEmpty { ContentUnavailableView("No measurements", systemImage: "ruler") } }
    }

    private func summary(_ m: BodyMeasurement) -> String {
        func len(_ name: String, _ cm: Double?) -> String? {
            cm.map { "\(name) \(String(format: "%.1f", lUnit.display($0)))\(lUnit.rawValue)" }
        }
        return [m.weightKg.map(wUnit.format), m.bodyFatPercent.map { String(format: "%.1f%% fat", $0) },
                len("Chest", m.chestCm), len("Waist", m.waistCm), len("Arm", m.armCm), len("Thigh", m.thighCm)]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
