# Aster camera magnification extension

This is a source-only fork of `mobile_scanner` 7.4.0. The upstream BSD license
is retained in `LICENSE`. Only runtime sources, package metadata and tests are
vendored; examples, screenshots and build artifacts are omitted.

Upstream repository: https://github.com/juliansteenbakker/mobile_scanner

Source archive: https://pub.dev/api/archives/mobile_scanner-7.4.0.tar.gz

Archive SHA-256:
`ce3f059ebd6dbfab7292bba0e893e354b46730636820d3c9ef69005ce2d55bce`

`UPSTREAM_FILES.sha256.json` records the original source-file hashes. The
package version is `7.4.0+aster.1`, and the application uses a repository path
dependency so a clean checkout includes the exact native implementation.

## Scope

The upstream `setZoomScale(0…1)` API is a normalized slider. Its platform
mappings differ and cannot truthfully drive controls labelled 1×, 2× and 3×.
The existing API remains unchanged for compatibility.

The additive public API is:

- `MobileScannerController.getZoomState()` → `Future<CameraZoomState>`
- `MobileScannerController.setZoomRatio(double)` → `Future<CameraZoomState>`
- `CameraZoomState`: `minZoomRatio`, `maxZoomRatio`, `zoomRatio`

The matching native channel methods are `getZoomState` and `setZoomRatio`.
Both return those three keys. The setter argument is a numeric ratio, and its
response contains the applied camera readback, rather than the requested value.

Android uses the active CameraX camera's hardware bounds and zoom ratio. The
setter waits for CameraX's operation future and rejects completions from a
paused, stopped or superseded camera session. iOS reads AVFoundation's current
available bounds, assigns the factor without a ramp, and reads it back. iOS
virtual-camera factors are normalized by the plugin's wide-camera baseline;
for example, native factor 2 on a virtual triple camera can represent 1×.

The Dart snapshot validates native data. Missing capabilities, stopped cameras,
unsupported platforms and failed requests never produce fabricated zoom ratios.
macOS and web retain the upstream API and explicitly reject the new ratio API.

No barcode detection, camera selection, permissions, image analysis or native
splash behavior is changed by this extension. The package's upstream dependency
versions are preserved. Remove this fork when an upstream release supplies an
equivalent confirmed-ratio and capability API, after parity tests pass.

## Verification

Run Dart tests from this package with `flutter test`. Run the Android package
unit tests through the application's Gradle project with
`:mobile_scanner:testDebugUnitTest`. The pure Swift conversion regression test
is `darwin/tests/CameraZoomSnapshotTests.swift`; compile it together with
`CameraZoomSnapshot.swift` using `swiftc`, then execute the resulting binary.
Application scanner tests additionally cover supported presets, confirmed
labels and lifecycle invalidation.
