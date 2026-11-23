import Foundation

/// Girth multipliers relative to a reference body, derived from a body measurement.
/// 1.0 means "same as reference". Missing measurements fall back to a weight-based estimate.
struct BodyShape: Equatable {
    var chest = 1.0, waist = 1.0, hips = 1.0, arms = 1.0
    var thighs = 1.0, calves = 1.0, shoulders = 1.0

    static let reference = BodyShape()

    private enum Ref {
        static let weightKg = 78.0, chest = 100.0, waist = 84.0, hips = 98.0
        static let arm = 33.0, thigh = 56.0, calf = 37.0, shoulders = 115.0
    }

    init() {}

    init(_ m: BodyMeasurement?) {
        guard let m else { return }
        // Girth scales roughly with the square root of mass for a fixed height.
        let fallback = m.weightKg.map { sqrt($0 / Ref.weightKg) } ?? 1.0
        func ratio(_ value: Double?, _ ref: Double) -> Double {
            min(max(value.map { $0 / ref } ?? fallback, 0.7), 1.6)
        }
        chest = ratio(m.chestCm, Ref.chest)
        waist = ratio(m.waistCm, Ref.waist)
        hips = ratio(m.hipsCm, Ref.hips)
        arms = ratio(m.armCm, Ref.arm)
        thighs = ratio(m.thighCm, Ref.thigh)
        calves = ratio(m.calfCm, Ref.calf)
        shoulders = ratio(m.shouldersCm, Ref.shoulders)
    }
}
