import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(HealthKitManager.self) private var health
    @Query(sort: \WorkoutSession.start, order: .reverse) private var sessions: [WorkoutSession]
    @AppStorage(SettingsKey.weightUnit) private var unit: WeightUnit = .lb

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !health.authorized {
                        connectCard
                    }

                    sectionTitle("Activity", subtitle: "Apple Watch · Polar")
                    LazyVGrid(columns: columns, spacing: 12) {
                        StatCard(title: "Steps", value: health.summary.steps.map { Int($0).formatted() },
                                 icon: "figure.walk", tint: .green)
                        StatCard(title: "Active energy", value: health.summary.activeEnergy.map { "\(Int($0)) kcal" },
                                 icon: "flame.fill", tint: .orange)
                        StatCard(title: "Resting HR", value: health.summary.restingHR.map { "\(Int($0)) bpm" },
                                 icon: "heart.fill", tint: .red)
                        StatCard(title: "HRV", value: health.summary.hrv.map { "\(Int($0)) ms" },
                                 icon: "waveform.path.ecg", tint: .pink)
                        StatCard(title: "Sleep", value: health.summary.sleepHours.map { String(format: "%.1f h", $0) },
                                 icon: "bed.double.fill", tint: .indigo)
                        StatCard(title: "Weight", value: health.summary.latestWeightKg.map(unit.format),
                                 icon: "scalemass.fill", tint: .teal)
                    }

                    sectionTitle("Nutrition today", subtitle: "MyFitnessPal via Apple Health")
                    LazyVGrid(columns: columns, spacing: 12) {
                        StatCard(title: "Calories", value: health.summary.calories.map { "\(Int($0)) kcal" },
                                 icon: "fork.knife", tint: .yellow)
                        StatCard(title: "Protein", value: health.summary.protein.map { "\(Int($0)) g" },
                                 icon: "bolt.fill", tint: .purple)
                        StatCard(title: "Carbs", value: health.summary.carbs.map { "\(Int($0)) g" },
                                 icon: "leaf.fill", tint: .mint)
                        StatCard(title: "Fat", value: health.summary.fat.map { "\(Int($0)) g" },
                                 icon: "drop.fill", tint: .brown)
                    }

                    sectionTitle("This week", subtitle: "GymApp")
                    let week = sessions.filter { $0.start > Calendar.current.date(byAdding: .day, value: -7, to: .now)! }
                    LazyVGrid(columns: columns, spacing: 12) {
                        StatCard(title: "Lifting sessions", value: "\(week.count)", icon: "dumbbell.fill", tint: .blue)
                        StatCard(title: "Volume lifted", value: unit.format(week.reduce(0) { $0 + $1.totalVolumeKg }),
                                 icon: "chart.bar.fill", tint: .cyan)
                    }

                    sectionTitle("Recent workouts", subtitle: "All sources")
                    if health.recentWorkouts.isEmpty {
                        Text(health.authorized ? "No workouts in the last 14 days." : "Connect Apple Health to see workouts.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(health.recentWorkouts) { w in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(w.name).font(.headline)
                                Text("\(w.start.formatted(.dateTime.weekday().month().day())) · \(w.source)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(Duration.seconds(w.duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                                if let e = w.energy { Text("\(Int(e)) kcal").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        .padding(12)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                    }

                    if let error = health.lastError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("Today")
            .refreshable { await health.refresh() }
            .task { await health.requestAuthorization() }
        }
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Connect Apple Health", systemImage: "heart.circle.fill").font(.headline)
            Text("Pulls in data from your Apple Watch, Polar (via Polar Flow) and MyFitnessPal.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("Connect") { Task { await health.requestAuthorization() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.bold())
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String?
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(tint)
            Text(value ?? "–").font(.title2.bold()).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }
}
