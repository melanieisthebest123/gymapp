import Foundation
import SwiftData

enum ExerciseLibrary {
    static let defaults: [(String, [MuscleGroup], [MuscleGroup])] = [
        ("Bench Press", [.chest], [.triceps, .shoulders]),
        ("Incline Dumbbell Press", [.chest, .shoulders], [.triceps]),
        ("Chest Fly", [.chest], []),
        ("Push-up", [.chest], [.triceps, .shoulders, .abs]),
        ("Dips", [.chest, .triceps], [.shoulders]),
        ("Overhead Press", [.shoulders], [.triceps, .traps]),
        ("Lateral Raise", [.shoulders], []),
        ("Face Pull", [.shoulders, .upperBack], [.traps]),
        ("Shrugs", [.traps], [.forearms]),
        ("Deadlift", [.hamstrings, .glutes, .lowerBack], [.traps, .forearms, .quads]),
        ("Romanian Deadlift", [.hamstrings, .glutes], [.lowerBack]),
        ("Barbell Row", [.upperBack, .lats], [.biceps, .lowerBack]),
        ("Pull-up", [.lats], [.biceps, .upperBack]),
        ("Lat Pulldown", [.lats], [.biceps]),
        ("Seated Cable Row", [.upperBack, .lats], [.biceps]),
        ("Barbell Curl", [.biceps], [.forearms]),
        ("Hammer Curl", [.biceps, .forearms], []),
        ("Tricep Pushdown", [.triceps], []),
        ("Skull Crusher", [.triceps], []),
        ("Squat", [.quads, .glutes], [.hamstrings, .lowerBack, .abs]),
        ("Front Squat", [.quads], [.glutes, .abs]),
        ("Leg Press", [.quads, .glutes], [.hamstrings]),
        ("Bulgarian Split Squat", [.quads, .glutes], [.hamstrings]),
        ("Leg Extension", [.quads], []),
        ("Leg Curl", [.hamstrings], []),
        ("Hip Thrust", [.glutes], [.hamstrings]),
        ("Calf Raise", [.calves], []),
        ("Plank", [.abs], [.obliques]),
        ("Cable Crunch", [.abs], []),
        ("Russian Twist", [.obliques], [.abs]),
        ("Hanging Leg Raise", [.abs], [.forearms]),
    ]

    static func seedIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Exercise>())) ?? 0
        guard count == 0 else { return }
        for (name, primary, secondary) in defaults {
            context.insert(Exercise(name: name, primary: primary, secondary: secondary))
        }
        try? context.save()
    }
}
