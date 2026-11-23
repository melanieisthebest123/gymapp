import Foundation
import Observation
import SwiftData
import Supabase

/// Keeps the on-device SwiftData store and the user's Supabase tables in step.
///
/// The phone is the source of truth while offline: every local insert/edit/delete is queued
/// (persisted in UserDefaults) and pushed when possible. A pull then applies changes made on
/// other devices, never overwriting records that still have unpushed local changes.
@MainActor
@Observable
final class SyncService {
    private(set) var isSyncing = false
    private(set) var lastSync: Date?
    private(set) var lastError: String?

    private let client = SupabaseConfig.client
    private let context: ModelContext
    private var userID: UUID?
    private var applyingRemote = false
    private var pushTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    private enum Key {
        static let upserts = "sync.pendingUpserts"
        static let deletes = "sync.pendingDeletes"
        static let migrated = "sync.migratedLocalData"
    }

    private enum Table {
        static let exercises = "exercises", sessions = "workout_sessions", entries = "exercise_entries"
        static let sets = "set_entries", measurements = "body_measurements"
    }

    private var pendingUpserts: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Key.upserts) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Key.upserts) }
    }
    private var pendingDeletes: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Key.deletes) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Key.deletes) }
    }

    init(context: ModelContext) {
        self.context = context
        observer = NotificationCenter.default.addObserver(
            forName: ModelContext.willSave, object: context, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recordLocalChanges() }
        }
    }

    // MARK: Lifecycle

    func signedIn(userID: UUID) async {
        self.userID = userID
        // Data logged before accounts existed gets uploaded to the first account that signs in.
        if !UserDefaults.standard.bool(forKey: Key.migrated) {
            markEverythingPending()
            UserDefaults.standard.set(true, forKey: Key.migrated)
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await pull()
        } catch {
            lastError = "Couldn't download your data: \(error.localizedDescription)"
        }
        if ((try? context.fetchCount(FetchDescriptor<Exercise>())) ?? 0) == 0 {
            ExerciseLibrary.seedIfNeeded(context)
        }
        do {
            try await push()
            lastSync = .now
            lastError = nil
        } catch {
            lastError = "Couldn't upload your data: \(error.localizedDescription)"
        }
    }

    /// Uploads anything pending, then wipes this device so the next account starts clean.
    func signOut() async {
        try? await push()
        wipeLocal()
    }

    func wipeLocal() {
        pushTask?.cancel()
        applyingRemote = true
        try? context.delete(model: SetEntry.self)
        try? context.delete(model: ExerciseEntry.self)
        try? context.delete(model: WorkoutSession.self)
        try? context.delete(model: BodyMeasurement.self)
        try? context.delete(model: Exercise.self)
        try? context.save()
        applyingRemote = false
        pendingUpserts = []
        pendingDeletes = []
        userID = nil
        lastSync = nil
    }

    func syncNow() async {
        guard userID != nil, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await push()
            try await pull()
            lastSync = .now
            lastError = nil
        } catch {
            lastError = "Sync failed: \(error.localizedDescription)"
        }
    }

    // MARK: Change tracking

    private func key(_ table: String, _ id: UUID) -> String { "\(table)|\(id.uuidString)" }

    private func key(for model: any PersistentModel) -> String? {
        switch model {
        case let m as Exercise: key(Table.exercises, m.uuid)
        case let m as WorkoutSession: key(Table.sessions, m.uuid)
        case let m as ExerciseEntry: key(Table.entries, m.uuid)
        case let m as SetEntry: key(Table.sets, m.uuid)
        case let m as BodyMeasurement: key(Table.measurements, m.uuid)
        default: nil
        }
    }

    private func recordLocalChanges() {
        guard !applyingRemote else { return }
        var ups = pendingUpserts, dels = pendingDeletes
        for model in context.insertedModelsArray + context.changedModelsArray {
            if let k = key(for: model) { ups.insert(k); dels.remove(k) }
        }
        for model in context.deletedModelsArray {
            if let k = key(for: model) { dels.insert(k); ups.remove(k) }
        }
        guard ups != pendingUpserts || dels != pendingDeletes else { return }
        pendingUpserts = ups
        pendingDeletes = dels
        schedulePush()
    }

    /// Batches rapid edits (typing reps, adding sets) into one upload a few seconds later.
    private func schedulePush() {
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, userID != nil else { return }
            do {
                try await push()
                lastSync = .now
                lastError = nil
            } catch {
                lastError = "Changes saved on this phone; will upload when online."
            }
        }
    }

    private func markEverythingPending() {
        var ups = pendingUpserts
        all(Exercise.self).forEach { ups.insert(key(Table.exercises, $0.uuid)) }
        all(WorkoutSession.self).forEach { ups.insert(key(Table.sessions, $0.uuid)) }
        all(ExerciseEntry.self).forEach { ups.insert(key(Table.entries, $0.uuid)) }
        all(SetEntry.self).forEach { ups.insert(key(Table.sets, $0.uuid)) }
        all(BodyMeasurement.self).forEach { ups.insert(key(Table.measurements, $0.uuid)) }
        pendingUpserts = ups
    }

    private func all<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    // MARK: Push

    func push() async throws {
        guard let uid = userID else { return }
        try? context.save()
        let ups = pendingUpserts, dels = pendingDeletes
        func ids(_ table: String, in keys: Set<String>) -> Set<UUID> {
            Set(keys.compactMap { k in
                let parts = k.split(separator: "|")
                return parts.count == 2 && parts[0] == table ? UUID(uuidString: String(parts[1])) : nil
            })
        }

        // Parents before children so foreign keys are satisfied.
        let exIDs = ids(Table.exercises, in: ups)
        try await upsert(Table.exercises, all(Exercise.self).filter { exIDs.contains($0.uuid) }.map {
            ExerciseRow(id: $0.uuid, user_id: uid, name: $0.name, primary_muscles: $0.primaryRaw,
                        secondary_muscles: $0.secondaryRaw, is_custom: $0.isCustom)
        })
        let sIDs = ids(Table.sessions, in: ups)
        try await upsert(Table.sessions, all(WorkoutSession.self).filter { sIDs.contains($0.uuid) }.map {
            SessionRow(id: $0.uuid, user_id: uid, start_at: $0.start, end_at: $0.end, notes: $0.notes)
        })
        let eIDs = ids(Table.entries, in: ups)
        try await upsert(Table.entries, all(ExerciseEntry.self).filter { eIDs.contains($0.uuid) }.compactMap { e in
            e.session.map { EntryRow(id: e.uuid, user_id: uid, session_id: $0.uuid,
                                     exercise_id: e.exercise?.uuid, position: e.order) }
        })
        let setIDs = ids(Table.sets, in: ups)
        try await upsert(Table.sets, all(SetEntry.self).filter { setIDs.contains($0.uuid) }.compactMap { s in
            s.entry.map { SetEntryRow(id: s.uuid, user_id: uid, entry_id: $0.uuid, position: s.order,
                                 reps: s.reps, weight_kg: s.weightKg, is_warmup: s.isWarmup) }
        })
        let mIDs = ids(Table.measurements, in: ups)
        try await upsert(Table.measurements, all(BodyMeasurement.self).filter { mIDs.contains($0.uuid) }.map {
            MeasurementRow(id: $0.uuid, user_id: uid, measured_at: $0.date, weight_kg: $0.weightKg,
                           body_fat_percent: $0.bodyFatPercent, chest_cm: $0.chestCm, waist_cm: $0.waistCm,
                           hips_cm: $0.hipsCm, arm_cm: $0.armCm, thigh_cm: $0.thighCm,
                           calf_cm: $0.calfCm, shoulders_cm: $0.shouldersCm)
        })
        pendingUpserts = pendingUpserts.subtracting(ups)

        // Children before parents (the database cascades anyway).
        for table in [Table.sets, Table.entries, Table.sessions, Table.measurements, Table.exercises] {
            let toDelete = ids(table, in: dels).map(\.uuidString)
            for chunk in toDelete.chunked(500) {
                try await client.from(table).delete().in("id", values: chunk).execute()
            }
        }
        pendingDeletes = pendingDeletes.subtracting(dels)
    }

    private func upsert<T: Encodable & Sendable>(_ table: String, _ rows: [T]) async throws {
        for chunk in rows.chunked(500) {
            try await client.from(table).upsert(chunk).execute()
        }
    }

    // MARK: Pull

    private func fetchAll<T: Decodable & Sendable>(_ table: String) async throws -> [T] {
        var result: [T] = []
        let page = 1000
        while true {
            let rows: [T] = try await client.from(table).select().order("id")
                .range(from: result.count, to: result.count + page - 1).execute().value
            result += rows
            if rows.count < page { return result }
        }
    }

    func pull() async throws {
        guard userID != nil else { return }
        async let exRows: [ExerciseRow] = fetchAll(Table.exercises)
        async let sRows: [SessionRow] = fetchAll(Table.sessions)
        async let eRows: [EntryRow] = fetchAll(Table.entries)
        async let setRows: [SetEntryRow] = fetchAll(Table.sets)
        async let mRows: [MeasurementRow] = fetchAll(Table.measurements)
        let (exercises, sessions, entries, sets, measurements) = try await (exRows, sRows, eRows, setRows, mRows)

        applyingRemote = true
        defer { applyingRemote = false }
        let pending = pendingUpserts.union(pendingDeletes)
        func isPending(_ table: String, _ id: UUID) -> Bool { pending.contains(key(table, id)) }

        // Exercises. A not-yet-uploaded local exercise with the same name adopts the cloud ID,
        // so the default library isn't duplicated across devices.
        var localEx = Dictionary(all(Exercise.self).map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        for row in exercises where localEx[row.id] == nil {
            let remoteIDs = Set(exercises.map(\.id))
            if let twin = localEx.values.first(where: { local in
                local.name == row.name && isPending(Table.exercises, local.uuid) && !remoteIDs.contains(local.uuid)
            }) {
                pendingUpserts.remove(key(Table.exercises, twin.uuid))
                localEx[twin.uuid] = nil
                twin.uuid = row.id
                localEx[row.id] = twin
            }
        }
        reconcile(rows: exercises, local: &localEx, table: Table.exercises, isPending: isPending,
                  make: { Exercise(name: $0.name, primary: [], secondary: []) },
                  apply: { m, r in m.name = r.name; m.primaryRaw = r.primary_muscles
                           m.secondaryRaw = r.secondary_muscles; m.isCustom = r.is_custom })

        var localS = Dictionary(all(WorkoutSession.self).map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        reconcile(rows: sessions, local: &localS, table: Table.sessions, isPending: isPending,
                  make: { _ in WorkoutSession() },
                  apply: { m, r in m.start = r.start_at; m.end = r.end_at; m.notes = r.notes })

        var localE = Dictionary(all(ExerciseEntry.self).map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        reconcile(rows: entries, local: &localE, table: Table.entries, isPending: isPending,
                  make: { _ in ExerciseEntry(exercise: nil, order: 0) },
                  apply: { m, r in m.order = r.position; m.session = localS[r.session_id]
                           m.exercise = r.exercise_id.flatMap { localEx[$0] } })

        var localSet = Dictionary(all(SetEntry.self).map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        reconcile(rows: sets, local: &localSet, table: Table.sets, isPending: isPending,
                  make: { _ in SetEntry(order: 0, reps: 0, weightKg: 0) },
                  apply: { m, r in m.order = r.position; m.reps = r.reps; m.weightKg = r.weight_kg
                           m.isWarmup = r.is_warmup; m.entry = localE[r.entry_id] })

        var localM = Dictionary(all(BodyMeasurement.self).map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        reconcile(rows: measurements, local: &localM, table: Table.measurements, isPending: isPending,
                  make: { _ in BodyMeasurement() },
                  apply: { m, r in m.date = r.measured_at; m.weightKg = r.weight_kg
                           m.bodyFatPercent = r.body_fat_percent; m.chestCm = r.chest_cm; m.waistCm = r.waist_cm
                           m.hipsCm = r.hips_cm; m.armCm = r.arm_cm; m.thighCm = r.thigh_cm
                           m.calfCm = r.calf_cm; m.shouldersCm = r.shoulders_cm })

        try context.save()
    }

    /// Inserts/updates local records from cloud rows and deletes local records that were
    /// deleted on another device. Records with unpushed local changes are left alone.
    private func reconcile<M: PersistentModel, R: RemoteRow>(
        rows: [R], local: inout [UUID: M], table: String, isPending: (String, UUID) -> Bool,
        make: (R) -> M, apply: (M, R) -> Void
    ) where M: HasUUID {
        let remoteIDs = Set(rows.map(\.id))
        for row in rows where !isPending(table, row.id) {
            let model: M
            if let existing = local[row.id] {
                model = existing
            } else {
                model = make(row)
                model.uuid = row.id
                context.insert(model)
                local[row.id] = model
            }
            apply(model, row)
        }
        for (id, model) in local where !remoteIDs.contains(id) && !isPending(table, id) {
            context.delete(model)
            local[id] = nil
        }
    }
}

// MARK: Rows (match supabase/schema.sql)

protocol RemoteRow: Codable, Sendable { var id: UUID { get } }
protocol HasUUID: AnyObject { var uuid: UUID { get set } }
extension Exercise: HasUUID {}
extension WorkoutSession: HasUUID {}
extension ExerciseEntry: HasUUID {}
extension SetEntry: HasUUID {}
extension BodyMeasurement: HasUUID {}

struct ExerciseRow: RemoteRow {
    let id: UUID; let user_id: UUID; let name: String
    let primary_muscles: [String]; let secondary_muscles: [String]; let is_custom: Bool
}
struct SessionRow: RemoteRow {
    let id: UUID; let user_id: UUID; let start_at: Date; let end_at: Date?; let notes: String
}
struct EntryRow: RemoteRow {
    let id: UUID; let user_id: UUID; let session_id: UUID; let exercise_id: UUID?; let position: Int
}
struct SetEntryRow: RemoteRow {
    let id: UUID; let user_id: UUID; let entry_id: UUID; let position: Int
    let reps: Int; let weight_kg: Double; let is_warmup: Bool
}
struct MeasurementRow: RemoteRow {
    let id: UUID; let user_id: UUID; let measured_at: Date
    let weight_kg: Double?; let body_fat_percent: Double?; let chest_cm: Double?; let waist_cm: Double?
    let hips_cm: Double?; let arm_cm: Double?; let thigh_cm: Double?; let calf_cm: Double?; let shoulders_cm: Double?
}

private extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
