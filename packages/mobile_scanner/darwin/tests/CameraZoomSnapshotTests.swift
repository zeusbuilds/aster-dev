import Foundation

@main
struct CameraZoomSnapshotTests {
    static func main() throws {
        let standard = try CameraZoomSnapshot(
            nativeMinimum: 1, nativeMaximum: 8, nativeCurrent: 3, standardFactor: 1
        )
        precondition(standard.serialized["zoomRatio"] == 3)
        let standardTwo = try standard.nativeFactor(for: 2)
        precondition(standardTwo == 2)

        // A virtual triple camera reports native factor 2 at standard 1×.
        let virtual = try CameraZoomSnapshot(
            nativeMinimum: 1, nativeMaximum: 20, nativeCurrent: 2, standardFactor: 2
        )
        precondition(virtual.minimum == 0.5)
        precondition(virtual.maximum == 10)
        precondition(virtual.current == 1)
        let virtualThree = try virtual.nativeFactor(for: 3)
        precondition(virtualThree == 6)

        let fixed = try CameraZoomSnapshot(
            nativeMinimum: 1, nativeMaximum: 1, nativeCurrent: 1, standardFactor: 1
        )
        let fixedOne = try fixed.nativeFactor(for: 1)
        precondition(fixedOne == 1)

        for invalid in [Double.nan, Double.infinity, -1, 0, 0.49, 10.1] {
            do {
                _ = try virtual.nativeFactor(for: invalid)
                fatalError("Invalid ratio was accepted: \(invalid)")
            } catch CameraZoomSnapshot.ValidationError.invalidRatio {}
        }
        do {
            _ = try CameraZoomSnapshot(
                nativeMinimum: 1, nativeMaximum: 4, nativeCurrent: 5, standardFactor: 1
            )
            fatalError("Inconsistent native state was accepted")
        } catch CameraZoomSnapshot.ValidationError.invalidCapabilities {}
        do {
            _ = try CameraZoomSnapshot(
                nativeMinimum: 1, nativeMaximum: 4, nativeCurrent: 1, standardFactor: 0
            )
            fatalError("Missing baseline was replaced with a default")
        } catch CameraZoomSnapshot.ValidationError.invalidCapabilities {}
        print("CameraZoomSnapshot: standard, virtual-camera, fixed-zoom and invalid-state regressions passed")
    }
}
