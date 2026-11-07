import Foundation

/// Converts AVFoundation factors into magnification relative to the wide camera.
/// A virtual multi-camera device can use factor 2 for its standard 1× field of
/// view. Using the native factor verbatim would mislabel that camera's zoom.
struct CameraZoomSnapshot {
    enum ValidationError: Error {
        case invalidCapabilities
        case invalidRatio
    }

    let minimum: Double
    let maximum: Double
    let current: Double
    let standardFactor: Double

    init(
        nativeMinimum: Double,
        nativeMaximum: Double,
        nativeCurrent: Double,
        standardFactor: Double
    ) throws {
        guard nativeMinimum.isFinite, nativeMinimum > 0,
              nativeMaximum.isFinite, nativeMaximum >= nativeMinimum,
              nativeCurrent.isFinite,
              nativeCurrent >= nativeMinimum - 0.0001,
              nativeCurrent <= nativeMaximum + 0.0001,
              standardFactor.isFinite, standardFactor > 0 else {
            throw ValidationError.invalidCapabilities
        }
        minimum = nativeMinimum / standardFactor
        maximum = nativeMaximum / standardFactor
        current = nativeCurrent / standardFactor
        self.standardFactor = standardFactor
    }

    func nativeFactor(for ratio: Double) throws -> Double {
        guard ratio.isFinite, ratio >= minimum, ratio <= maximum else {
            throw ValidationError.invalidRatio
        }
        return ratio * standardFactor
    }

    var serialized: [String: Double] {
        ["minZoomRatio": minimum, "maxZoomRatio": maximum, "zoomRatio": current]
    }
}
