import SwiftUI

struct SettingsView: View {
    @Environment(HealthKitManager.self) private var health
    @Environment(AuthManager.self) private var auth
    @Environment(SyncService.self) private var sync
    @State private var confirmingDelete = false
    @AppStorage(SettingsKey.weightUnit) private var weightUnit: WeightUnit = .lb
    @AppStorage(SettingsKey.lengthUnit) private var lengthUnit: LengthUnit = .inch
    @AppStorage(SettingsKey.saveToHealth) private var saveToHealth = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Signed in as", value: auth.email ?? "Apple ID")
                    HStack {
                        Button("Sync now") { Task { await sync.syncNow() } }
                            .disabled(sync.isSyncing)
                        Spacer()
                        if sync.isSyncing {
                            ProgressView()
                        } else if let last = sync.lastSync {
                            Text("Synced \(last.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let error = sync.lastError {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                    Button("Sign out") {
                        Task {
                            await sync.signOut()
                            await auth.signOut()
                        }
                    }
                    Button("Delete account", role: .destructive) { confirmingDelete = true }
                } header: {
                    Text("Account")
                } footer: {
                    Text("Your workouts and measurements are saved to your account and stay on this phone for offline use.")
                }

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
            .confirmationDialog("Delete your account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete account and all data", role: .destructive) {
                    Task {
                        if await auth.deleteAccount() { sync.wipeLocal() }
                    }
                }
            } message: {
                Text("This permanently deletes your account and every workout and measurement saved to it. This can't be undone.")
            }
            .alert("Couldn't delete account", isPresented: Binding(
                get: { auth.errorMessage != nil && auth.session != nil },
                set: { if !$0 { auth.errorMessage = nil } })) {
                Button("OK") {}
            } message: {
                Text(auth.errorMessage ?? "")
            }
        }
    }
}
