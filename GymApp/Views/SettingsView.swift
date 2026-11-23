import SwiftUI

struct SettingsView: View {
    @Environment(HealthKitManager.self) private var health
    @AppStorage(SettingsKey.weightUnit) private var weightUnit: WeightUnit = .lb
    @AppStorage(SettingsKey.lengthUnit) private var lengthUnit: LengthUnit = .inch
    @AppStorage(SettingsKey.saveToHealth) private var saveToHealth = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Weight", selection: $weightUnit) {
                        ForEach(WeightUnit.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Measurements", selection: $lengthUnit) {
                        ForEach(LengthUnit.allCases) { Text($0.rawValue).tag($0) }
                    }
                }

                Section {
                    Toggle("Save workouts & weight to Health", isOn: $saveToHealth)
                    Button("Connect / re-check Apple Health") {
                        Task { await health.requestAuthorization() }
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("To change what GymApp can read, open the Health app → your profile → Apps → GymApp.")
                }

                Section("Connect your other apps") {
                    DisclosureGroup("Apple Watch") {
                        Text("Nothing to do. Apple Watch data goes into Apple Health automatically.")
                    }
                    DisclosureGroup("Polar watch") {
                        Text("Open the Polar Flow app → General settings → Apple Health → turn it on. Your Polar workouts, heart rate and sleep will then show up in GymApp.")
                    }
                    DisclosureGroup("MyFitnessPal") {
                        Text("Open MyFitnessPal → More → Sync Apps & Devices → Apple Health → Connect, and allow it to write nutrition and weight. Your calories and macros will then show on the Today tab.")
                    }
                }
                .font(.subheadline)
            }
            .navigationTitle("Settings")
        }
    }
}
