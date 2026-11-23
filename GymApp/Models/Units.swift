import Foundation

/// All weights are stored in kilograms and lengths in centimetres; these helpers convert for display.
enum WeightUnit: String, CaseIterable, Identifiable {
    case kg, lb
    var id: String { rawValue }
    static let kgPerLb = 0.45359237

    func display(_ kg: Double) -> Double { self == .kg ? kg : kg / Self.kgPerLb }
    func toKg(_ value: Double) -> Double { self == .kg ? value : value * Self.kgPerLb }
    func format(_ kg: Double) -> String {
        let v = display(kg)
        return (v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)) + " \(rawValue)"
    }
}

enum LengthUnit: String, CaseIterable, Identifiable {
    case cm, inch = "in"
    var id: String { rawValue }
    func display(_ cm: Double) -> Double { self == .cm ? cm : cm / 2.54 }
    func toCm(_ value: Double) -> Double { self == .cm ? value : value * 2.54 }
}

enum SettingsKey {
    static let weightUnit = "weightUnit"
    static let lengthUnit = "lengthUnit"
    static let saveToHealth = "saveWorkoutsToHealth"
}
