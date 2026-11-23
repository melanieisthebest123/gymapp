import SwiftUI
import SwiftData

@main
struct GymAppMain: App {
    private let container: ModelContainer
    @State private var health = HealthKitManager()
    @State private var auth = AuthManager()
    @State private var sync: SyncService

    init() {
        let container = try! ModelContainer(for: Exercise.self, WorkoutSession.self, ExerciseEntry.self,
                                            SetEntry.self, BodyMeasurement.self)
        self.container = container
        _sync = State(initialValue: SyncService(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environment(health)
                .environment(auth)
                .environment(sync)
                .task { await auth.start() }
        }
        .modelContainer(container)
    }
}

/// Shows the sign-in screen until there's an account session, then the app.
struct AppRoot: View {
    @Environment(AuthManager.self) private var auth
    @Environment(SyncService.self) private var sync
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if auth.isLoading {
                ProgressView()
            } else if let userID = auth.userID {
                RootTabView()
                    .task(id: userID) { await sync.signedIn(userID: userID) }
            } else {
                AuthView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await sync.syncNow() }
            case .background: Task { try? await sync.push() }
            default: break
            }
        }
    }
}

struct RootTabView: View {
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
    }
}
