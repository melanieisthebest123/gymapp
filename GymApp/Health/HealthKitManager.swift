import Foundation
import HealthKit
import Observation

/// Single gateway to Apple Health. Apple Watch writes here natively; Polar Flow and
/// MyFitnessPal both sync into Apple Health when enabled in their own settings,
/// so reading from HealthKit covers all three sources.
@MainActor
@Observable
final class HealthKitManager {
    struct DaySummary {
        var steps: Double?
        var activeEnergy: Double?
        var restingHR: Double?
        var hrv: Double?
        var sleepHours: Double?
        var latestWeightKg: Double?
        var calories: Double?
        var protein: Double?
        var carbs: Double?
        var fat: Double?
    }

    struct WorkoutItem: Identifiable {
        let id: UUID
        let name: String
        let start: Date
        let duration: TimeInterval
        let energy: Double?
        let source: String
    }

    let store = HKHealthStore()
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var authorized = false
    var summary = DaySummary()
    var recentWorkouts: [WorkoutItem] = []
    var weightHistory: [(date: Date, kg: Double)] = []
    var lastError: String?

    private var readTypes: Set<HKObjectType> {
        let quantities: [HKQuantityTypeIdentifier] = [
            .stepCount, .activeEnergyBurned, .restingHeartRate, .heartRate,
            .heartRateVariabilitySDNN, .bodyMass, .bodyFatPercentage,
            .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal,
        ]
        var set: Set<HKObjectType> = Set(quantities.map { HKQuantityType($0) })
        set.insert(HKCategoryType(.sleepAnalysis))
        set.insert(HKObjectType.workoutType())
        return set
    }

    private var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKQuantityType(.bodyMass), HKQuantityType(.activeEnergyBurned)]
    }

    func requestAuthorization() async {
        guard isAvailable else { lastError = "Health data isn't available on this device."; return }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            authorized = true
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refresh() async {
        guard isAvailable else { return }
        let startOfDay = Calendar.current.startOfDay(for: .now)
        async let steps = sum(.stepCount, unit: .count(), from: startOfDay)
        async let energy = sum(.activeEnergyBurned, unit: .kilocalorie(), from: startOfDay)
        async let calories = sum(.dietaryEnergyConsumed, unit: .kilocalorie(), from: startOfDay)
        async let protein = sum(.dietaryProtein, unit: .gram(), from: startOfDay)
        async let carbs = sum(.dietaryCarbohydrates, unit: .gram(), from: startOfDay)
        async let fat = sum(.dietaryFatTotal, unit: .gram(), from: startOfDay)
        async let resting = latest(.restingHeartRate, unit: .count().unitDivided(by: .minute()))
        async let hrv = latest(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let weight = latest(.bodyMass, unit: .gramUnit(with: .kilo))
        async let sleep = sleepLastNight()
        async let workouts = fetchWorkouts(days: 14)
        async let weights = fetchWeightHistory(days: 180)

        summary = DaySummary(
            steps: await steps, activeEnergy: await energy, restingHR: await resting,
            hrv: await hrv, sleepHours: await sleep, latestWeightKg: await weight,
            calories: await calories, protein: await protein, carbs: await carbs, fat: await fat)
        recentWorkouts = await workouts
        weightHistory = await weights
    }

    // MARK: Reading

    private func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date) async -> Double? {
        let predicate = HKSamplePredicate.quantitySample(
            type: HKQuantityType(id),
            predicate: HKQuery.predicateForSamples(withStart: start, end: .now))
        let query = HKStatisticsQueryDescriptor(predicate: predicate, options: .cumulativeSum)
        return try? await query.result(for: store)?.sumQuantity()?.doubleValue(for: unit)
    }

    private func latest(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 1)
        return try? await query.result(for: store).first?.quantity.doubleValue(for: unit)
    }

    /// Hours asleep since 6pm yesterday. Overlapping samples (e.g. Apple Watch and Polar
    /// both recording the same night) are merged so sleep isn't double counted.
    private func sleepLastNight() async -> Double? {
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .hour, value: -6, to: cal.startOfDay(for: .now)) else { return nil }
        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let query = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis),
                                         predicate: HKQuery.predicateForSamples(withStart: start, end: .now))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        guard let samples = try? await query.result(for: store) else { return nil }
        let intervals = samples.filter { asleep.contains($0.value) }.map { ($0.startDate, $0.endDate) }
        guard !intervals.isEmpty else { return nil }

        var total: TimeInterval = 0
        var current = intervals[0]
        for next in intervals.dropFirst() {
            if next.0 <= current.1 {
                current.1 = max(current.1, next.1)
            } else {
                total += current.1.timeIntervalSince(current.0)
                current = next
            }
        }
        total += current.1.timeIntervalSince(current.0)
        return total / 3600
    }

    private func fetchWorkouts(days: Int) async -> [WorkoutItem] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let query = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: .now))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)], limit: 50)
        guard let workouts = try? await query.result(for: store) else { return [] }
        return workouts.map { w in
            let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie())
            return WorkoutItem(id: w.uuid, name: w.workoutActivityType.displayName,
                               start: w.startDate, duration: w.duration, energy: kcal,
                               source: w.sourceRevision.source.name)
        }
    }

    private func fetchWeightHistory(days: Int) async -> [(date: Date, kg: Double)] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass),
                                         predicate: HKQuery.predicateForSamples(withStart: start, end: .now))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        guard let samples = try? await query.result(for: store) else { return [] }
        return samples.map { ($0.startDate, $0.quantity.doubleValue(for: .gramUnit(with: .kilo))) }
    }

    // MARK: Writing

    func saveStrengthWorkout(start: Date, end: Date, totalVolumeKg: Double) async {
        guard isAvailable else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.endCollection(at: end)
            try await builder.addMetadata(["GymAppTotalVolumeKg": totalVolumeKg])
            _ = try await builder.finishWorkout()
        } catch {
            lastError = "Couldn't save workout to Health: \(error.localizedDescription)"
        }
    }

    func saveBodyMass(kg: Double, date: Date) async {
        guard isAvailable else { return }
        let sample = HKQuantitySample(type: HKQuantityType(.bodyMass),
                                      quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg),
                                      start: date, end: date)
        do { try await store.save(sample) } catch {
            lastError = "Couldn't save weight to Health: \(error.localizedDescription)"
        }
    }
}

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .traditionalStrengthTraining: "Strength Training"
        case .functionalStrengthTraining: "Functional Strength"
        case .running: "Run"
        case .walking: "Walk"
        case .cycling: "Cycling"
        case .swimming: "Swim"
        case .highIntensityIntervalTraining: "HIIT"
        case .yoga: "Yoga"
        case .rowing: "Rowing"
        case .elliptical: "Elliptical"
        case .stairClimbing: "Stairs"
        case .hiking: "Hike"
        case .coreTraining: "Core"
        case .crossTraining: "Cross Training"
        default: "Workout"
        }
    }
}
