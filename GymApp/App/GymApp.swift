import SwiftUI
import SwiftData

@main
struct GymAppMain: App {
    @State private var health = HealthKitManager()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(health)
        }
        .modelContainer(for: [Exercise.self, WorkoutSession.self, ExerciseEntry.self,
                              SetEntry.self, BodyMeasurement.self])
    }
}

struct RootTabView: View {
    @Environment(\.modelContext) private var context

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Today", systemImage: "heart.text.square") }
            WorkoutListView()
                .tabItem { Label("Workouts", systemImage: "dumbbell") }
            BodyView()
                .tabItem { Label("Body", systemImage: "figure.stand") }
            StatsView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .task { ExerciseLibrary.seedIfNeeded(context) }
    }
}
